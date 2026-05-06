let host = "{{{TOH_DATABASE_INIT_HOST}}}"
let user = "{{{TOH_DATABASE_INIT_USER}}}"
let certs_dir = "{{{TOH_DATABASE_INIT_CERTS_DIR}}}"
let database_url = "{{{TOH_DATABASE_INIT_DATABASE_URL}}}"
let hash = "{{{TOH_DATABASE_INIT_HASH}}}"
let init_command = "{{{TOH_DATABASE_INIT_COMMAND}}}"
let sql_scripts = "{{{TOH_DATABASE_INIT_SQL_SCRIPTS}}}"
  | split row ,
  | each {
      let split = $in | split row ":";
      { name: $split.0 path: $split.1 }
    }
let nushell_scripts = "{{{TOH_DATABASE_INIT_NUSHELL_SCRIPTS}}}"
  | split row ,
  | each {
      let split = $in | split row ":";
      { name: $split.0 path: $split.1 }
    }

def "main" [
  --max-attempts: int = 10,
  --retry-delay: int = 5,
  --init-timeout: int = 30,
  --script-timeout: int = 600,
  --wait-timeout: int = 3600
] {
  try {
    database initialize cluster
  } catch { |e|
    let data = $e.msg | from json
    print -e $data.msg
    exit 1
  }

  try {
    database initialize database
  } catch { |e|
    let data = $e.msg | from json
    print -e $data.msg
    exit 1
  }

  let lock = (try {
      database lock initialization
    } catch { |e|
      let data = $e.msg | from json
      print -e $data.msg
      exit 1
    })
  if $lock.completed {
    exit 0
  }

  if $lock.acquired {
    try {
      if $lock.failure == null {
        database initialize sql
        database initialize nushell
      } else {
        if $lock.failure.type == sql {
          database initialize sql $lock.failure.name
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
        let inner_data = $e.msg | from json
        print -e $inner_data.msg
      }

      print -e $data.msg
      exit 1
    }

    try {
      database record initialization success
    } catch { |e|
      let data = $e.msg | from json
      print -e $data.msg
      exit 1
    }
  } else {
    try {
      database wait initialization
    } catch { |e|
      let data = $e.msg | from json
      print -e $data.msg
      exit 1
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
          runuser -u $user --
            nu -c $init_command
      ) | complete

      if $output.exit_code == 0 {
        print "Cluster initialized successfully"
        break
      }

      if ($output.stdout | str contains "cluster has already been initialized") {
        print "Cluster already initialized, continuing..."
        break
      }

      if $attempt == $max_attempts {
        error make {
          msg: ({
            msg: (
              $"Failed to initialize cluster after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          } | to json)
        }
      }

      print (
        $"Initialization attempt ($attempt) failed with output '($output.stdout)'"
        + $", retrying in ($retry_delay) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "database initialize database" [] {
    print "Setting up initialization table..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($script_timeout)s"
          runuser -u $user --
            psql $database_url --set=ON_ERROR_STOP=1 -c `
              CREATE DATABASE IF NOT EXISTS __toh_initialization;
              USE __toh_initialization;
              CREATE TABLE IF NOT EXISTS initializations (
                hash STRING PRIMARY KEY,
                status STRING,
                timestamp TIMESTAMP DEFAULT now(),
                type STRING DEFAULT null,
                name STRING DEFAULT null
              );
            `
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization table ready"
        break
      }

      if $attempt == $max_attempts {
        error make {
          msg: ({
            msg: (
              $"Failed to create initialization table after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          } | to json)
        }
      }

      print (
        $"Initialization table setup attempt ($attempt) failed"
        + $", retrying in ($max_attempts) seconds..."
      )
      sleep ($retry_delay | into duration --unit sec)
    }
  }

  def "database lock initialization" [
  ]: nothing -> record<acquired: bool, completed: bool, failure: record<type: string, name: string>> {
    print "Locking initialization..."

    for attempt in 1..$max_attempts {
      let sql = $"
        WITH
          update_failed AS \(
            UPDATE __toh_initialization.initializations
            SET status = 'running', timestamp = now\(\)
            WHERE hash = '($hash)' AND status = 'failed'
            RETURNING type, name
          \),
          insert_new AS \(
            INSERT INTO __toh_initialization.initializations \(hash, status\)
            VALUES \('($hash)', 'running'\)
            ON CONFLICT \(hash\) DO NOTHING
            RETURNING 1 AS dummy
          \)
        SELECT
          CASE WHEN EXISTS\(SELECT 1 FROM insert_new\)
                 OR EXISTS\(SELECT 1 FROM update_failed\) THEN 'true'
               ELSE 'false'
          END AS acquired,
          CASE WHEN EXISTS\(SELECT 1 FROM insert_new\)
                 OR EXISTS\(SELECT 1 FROM update_failed\) THEN 'false'
               ELSE COALESCE\(
                 \(SELECT 'true' FROM __toh_initialization.initializations
                  WHERE hash = '($hash)' AND status = 'completed'\),
                 'false'
               \)
          END AS completed,
          COALESCE\(\(SELECT type FROM update_failed\), ''\) AS failure_type,
          COALESCE\(\(SELECT name FROM update_failed\), ''\) AS failure_name
      "

      let output = (
        timeout $"($init_timeout)s"
          runuser -u $user --
            psql $database_url -t -A -F '|' -c $sql
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
        error make {
          msg: ({
            msg: (
              $"Locking initialization failed after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          } | to json)
        }
      }

      print (
        $"Initialization lock attempt ($attempt) failed"
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
          runuser -u $user --
            psql -t $database_url -c $"
              USE __toh_initialization;
              SELECT hash
              FROM initializations
              WHERE hash = '($hash)'
              AND status = 'completed'
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
      error make {
        msg: ({
          msg: (
            $"Timeout waiting for initialization to complete after ($wait_timeout)s"
            + $":\n($output.stderr)"
          )
        } | to json)
      }
    }
  }

  def "database record initialization success" [] {
    print "Recording successful initialization completion..."
    for attempt in 1..$max_attempts {
      let output = (
        timeout $"($script_timeout)s"
          runuser -u $user --
            psql $database_url --set=ON_ERROR_STOP=1 -c $"
              USE __toh_initialization;
              INSERT INTO initializations \(hash, status\)
              VALUES \('($hash)', 'completed'\)
              ON CONFLICT \(hash\) DO NOTHING;
            "
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization success recorded successfully"
        break
      }

      if $attempt == $max_attempts {
        error make {
          msg: ({
            msg: (
              $"Failed to record initialization success after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          } | to json)
        }
      }

      print (
        $"Successful initialization record attempt ($attempt) failed"
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
          runuser -u $user --
            psql $database_url --set=ON_ERROR_STOP=1 -c $"
              USE __toh_initialization;
              INSERT INTO initializations \(hash, status, type, name\)
              VALUES \('($hash)', 'failed', '($type)', '($name)'\)
              ON CONFLICT \(hash\) DO NOTHING;
            "
      ) | complete

      if $output.exit_code == 0 {
        print "Initialization failure recorded successfully"
        break
      }

      if $attempt == $max_attempts {
        error make {
          msg: ({
            msg: (
              $"Failed to record initialization failure after ($max_attempts) attempts"
              + $":\n($output.stderr)"
            )
          } | to json)
        }
      }

      print (
        $"Failed initialization record attempt ($attempt) failed"
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
            runuser -u $user --
              psql $database_url --set=ON_ERROR_STOP=1 -c $"
                USE __toh_initialization;
                \\i ($script.path)
              "
        ) | complete

        if $output.exit_code == 0 {
          print $"SQL script ($script) completed successfully"
          break
        }

        if $attempt == $max_attempts {
          error make {
            msg: ({
              msg: (
                $"SQL script ($script) failed after ($max_attempts) attempts"
                + $":\n($output.stderr)"
              )
              type: sql
              name: $script.name
            } | to json)
          }
        }

        print (
          $"SQL script ($script) attempt ($attempt) failed"
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
          error make {
            msg: ({
              msg: (
                $"Nushell script ($script) failed after ($max_attempts) attempts"
                + $":\n($output.stderr)"
              )
              type: nushell
              name: $script.name
            } | to json)
          }
        }

        print (
          $"Nushell script ($script) attempt ($attempt) failed"
          + $", retrying in ($retry_delay) seconds..."
        )
        sleep ($retry_delay | into duration --unit sec)
      }
    }
    print "All nushell scripts completed"
  }
}
