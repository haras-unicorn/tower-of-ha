let database_env_file = "{{{TOH_DATABASE_INIT_DATABASE_ENV_FILE}}}"
let hash = "{{{TOH_DATABASE_INIT_HASH}}}"
let init_command = r#'{{{TOH_DATABASE_INIT_COMMAND}}}'#
let sql_scripts = "{{{TOH_DATABASE_INIT_SQL_SCRIPTS}}}" | from json
let nushell_scripts = "{{{TOH_DATABASE_INIT_NUSHELL_SCRIPTS}}}" | from json
let systemd_units = "{{{TOH_DATABASE_INIT_SYSTEMD_UNITS}}}" | from json

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --init-timeout: int = 30,
  --script-timeout: int = 600,
  --wait-timeout: int = 3600
] {
  open --raw $database_env_file | from toml | load-env

  try {
    database initialize cluster
  } catch { |e|
    database handle error $e
  }

  try {
    database initialize database
  } catch { |e|
    database handle error $e
  }

  let lock = (try {
      database lock initialization
    } catch { |e|
      database handle error $e
    })
  if $lock.completed {
    exit 0
  }

  if $lock.acquired {
    try {
      if $lock.failure == null {
        database initialize sql
        database initialize systemd
        database initialize nushell
      } else {
        if $lock.failure.type == sql {
          database initialize sql $lock.failure.name
          database initialize systemd
          database initialize nushell
        } else if $lock.failure.type == systemd {
          database initialize systemd $lock.failure.name
          database initialize nushell
        } else {
          database initialize nushell $lock.failure.name
        }
      }
    } catch { |e|
      let data = $e.msg | from json
      try {
        database record initialization failure $data.type $data.name
      } catch { |e|
        database handle error $e
      }

      database handle error $e
    }

    try {
      database record initialization success
    } catch { |e|
      database handle error $e
    }
  } else {
    try {
      database wait initialization
    } catch { |e|
      database handle error $e
    }
  }

  print (
    "Database initialization complete"
    + $" with latest hash '($hash)'"
  )

  def "database initialize cluster" [] {
    print "Initializing database cluster..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($init_timeout)s"
          nu -c $init_command
      ) | complete

      if $output.exit_code == 0 {
        print "Cluster initialized successfully"
        break
      }

      if $attempt == $max_attempts {
        database make error {
          msg: (
            $"Failed to initialize cluster after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Initialization attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "database initialize database" [] {
    print "Setting up initialization table..."
    let initialization_file = mktemp -t
    echo `
      select 'create database __toh_initialization'
      where not exists (select from pg_database where datname = '__toh_initialization')\gexec
      \c __toh_initialization
      create table if not exists initializations (
        hash text primary key,
        status text,
        timestamp timestamp with time zone default now(),
        type text default null,
        name text default null
      );
    ` | save -f $initialization_file
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($script_timeout)s"
          psql
            --set=ON_ERROR_STOP=on
            -f $initialization_file
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization table ready"
        rm -f $initialization_file
        break
      }

      if $attempt == $max_attempts {
        rm -f $initialization_file
        database make error {
          msg: (
            $"Failed to create initialization table after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Initialization table setup attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($max_attempts) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }

    rm -f $initialization_file
  }

  def "database lock initialization" [
  ]: nothing -> record<acquired: bool, completed: bool, failure: record<type: string, name: string>> {
    print "Locking initialization..."

    for attempt in 1..$max_attempts {
      let sql = $"
        with
          update_failed as \(
            update initializations
            set status = 'running', timestamp = now\(\)
            where hash = '($hash)' and status = 'failed'
            returning type, name
          \),
          insert_new as \(
            insert into initializations \(hash, status\)
            values \('($hash)', 'running'\)
            on conflict \(hash\) do nothing
            returning 1 as dummy
          \)
        select
          case when exists\(select 1 from insert_new\)
                 or exists\(select 1 from update_failed\) then 'true'
               else 'false'
          end as acquired,
          case when exists\(select 1 from insert_new\)
                 or exists\(select 1 from update_failed\) then 'false'
               else coalesce\(
                 \(select 'true' from initializations
                  where hash = '($hash)' and status = 'completed'\),
                 'false'
               \)
          end as completed,
          coalesce\(\(select type from update_failed\), ''\) as failure_type,
          coalesce\(\(select name from update_failed\), ''\) as failure_name
      "

      let output = (
        timeout $"($init_timeout)s"
          psql -d __toh_initialization -t -A -F '|' -c $sql
      ) | complete

      if $output.exit_code == 0 {
        let parts = ($output.stdout | str trim | split row "|")
        let acquired = ($parts.0 == "true")
        let completed = ($parts.1 == "true")

        if $acquired and $parts.2 != "" {
          print "Initialization lock acquired (resuming from previous failure)"
          return {
            acquired: true,
            completed: false,
            failure: { type: $parts.2, name: $parts.3 }
          }
        }

        if $acquired {
          print "Initialization lock acquired"
          return { acquired: true, completed: false, failure: null }
        }

        if $completed {
          print "Initialization already completed"
          return { acquired: false, completed: true, failure: null }
        }

        print "Initialization already running"
        return { acquired: false, completed: false, failure: null }
      }

      if $attempt == $max_attempts {
        database make error {
          msg: (
            $"Locking initialization failed after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Initialization lock attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay)s..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }

    return { acquired: false, completed: false, failure: null }
  }

  def "database wait initialization" [] {
    print (
      "Waiting for an ongoing initialization to complete"
      + $" \(hash: '($hash)'\)..."
    )
    mut waited = 0
    mut output = { }
    while $waited < $wait_timeout {
      $output = (
        timeout $"($script_timeout)s"
          psql -d __toh_initialization -t -c $"
            select hash
            from initializations
            where hash = '($hash)'
            and status = 'completed'
          "
      ) | complete

      if ($output.exit_code == 0
        and ($output.stdout | str trim) == $hash) {
        print "Initialization completed successfully"
        break
      }

      print (
        $"Initialization not yet complete \(output is '($output.stdout)'\)"
        + $", waiting... \(($waited)/($wait_timeout) seconds\)"
      )
      sleep ($retry_delay | into duration --unit sec)
      $waited = $waited + $retry_delay
    }

    if $waited >= $wait_timeout {
      database make error {
        msg: (
          $"Timeout waiting for initialization to complete after ($wait_timeout)s"
          + $":\n($output.stderr)"
        )
      }
    }
  }

  def "database record initialization success" [] {
    print "Recording successful initialization completion..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($script_timeout)s"
          psql
            -d __toh_initialization
            --set=ON_ERROR_STOP=on
            -c $"
              insert into initializations \(hash, status\)
              values \('($hash)', 'completed'\)
              on conflict \(hash\) do update set status = 'completed', timestamp = now\(\);
            "
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization success recorded successfully"
        break
      }

      if $attempt == $max_attempts {
        database make error {
          msg: (
            $"Failed to record initialization success after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Successful initialization record attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "database record initialization failure" [
    type: string,
    name: string
  ] {
    print "Recording failed initialization..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($script_timeout)s"
          psql
            -d __toh_initialization
            --set=ON_ERROR_STOP=on
            -c $"
              insert into initializations \(hash, status, type, name\)
              values \('($hash)', 'failed', '($type)', '($name)'\)
              on conflict \(hash\) do update set status = 'failed', type = '($type)', name = '($name)';
            "
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization failure recorded successfully"
        break
      }

      if $attempt == $max_attempts {
        database make error {
          msg: (
            $"Failed to record initialization failure after ($max_attempts) attempts"
            + $":\n($output.stderr)"
          )
        }
      }

      print (
        $"Failed initialization record attempt ($attempt) failed"
        + $" with stdout '($output.stdout)'"
        + $" and stderr '($output.stderr)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "database initialize sql" [
    from?: string
  ] {
    let sql_scripts_to_run = if $from == null {
      print $"Running all SQL scripts..."
      $sql_scripts
    } else {
      print $"Resuming SQL scripts from '($from)'..."
      $sql_scripts | skip until { $in.name == $from }
    }

    for script in $sql_scripts_to_run {
      print $"Running SQL script: ($script)"
      for attempt in 1..$max_attempts {
        let output = (
          timeout $"($script_timeout)s"
            psql
              --set=ON_ERROR_STOP=on
              -f $script.path
        ) | complete

        if $output.exit_code == 0 {
          print $"SQL script ($script) completed successfully"
          break
        }

        if $attempt == $max_attempts {
          database make error {
            msg: (
              $"SQL script ($script) failed after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
            type: sql
            name: $script.name
          }
        }

        print (
          $"SQL script ($script) attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
    print "All SQL scripts completed"
  }

  def "database initialize nushell" [
    from?: string
  ] {
    let nushell_scripts_to_run = if $from == null {
      print $"Running all nushell scripts..."
      $nushell_scripts
    } else {
      print $"Resuming nushell scripts from '($from)'..."
      $nushell_scripts | skip until { $in.name == $from }
    }

    for script in $nushell_scripts_to_run {
      print $"Running nushell script: ($script)"
      for attempt in 1..$max_attempts {
        let output = timeout $"($script_timeout)s" nu $script.path
          | complete

        if $output.exit_code == 0 {
          print $"Nushell script ($script) completed successfully"
          break
        }

        if $attempt == $max_attempts {
          database make error {
            msg: (
              $"Nushell script ($script) failed after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
            type: nushell
            name: $script.name
          }
        }

        print (
          $"Nushell script ($script) attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
    print "All nushell scripts completed"
  }

  def "database initialize systemd" [
    from?: string
  ] {
    let systemd_units_to_run = if $from == null {
      print $"Running all systemd units..."
      $systemd_units
    } else {
      print $"Resuming systemd units from '($from)'..."
      $systemd_units | skip until { $in.name == $from }
    }

    for unit in $systemd_units_to_run {
      print $"Running systemd unit: ($unit)"
      for attempt in 1..$max_attempts {
        let output = timeout $"($script_timeout)s" systemctl start $unit.unit
          | complete

        if $output.exit_code == 0 {
          print $"systemd unit ($unit) completed successfully"
          break
        }

        if $attempt == $max_attempts {
          database make error {
            msg: (
              $"systemd unit ($unit) failed after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
            type: systemd
            name: $unit.name
          }
        }

        print (
          $"systemd unit ($unit) attempt ($attempt) failed"
          + $" with stdout '($output.stdout)'"
          + $" and stderr '($output.stderr)'"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
    print "All systemd units completed"
  }

  def "database make error" [msg] {
    error make {
      msg: ($msg | to json)
    }
  }

  def "database handle error" [e] {
    let data = $e.msg | from json
    if ($data | describe) == "string" {
      print -e $e.msg
    } else {
      print -e $data.msg
    }
    exit 1
  }
}
