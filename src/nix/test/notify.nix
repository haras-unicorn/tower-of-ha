# NOTE: the test driver of nixos-26.05 reads the notify socket of a container
# only until the container is ready, but the init of the container sends to it
# for as long as it runs; once its queue is full, the init blocks on the send,
# so it stops reaping and answering, and systemctl inside fails with "Transport
# endpoint is not connected"; nixpkgs master drains the socket for the whole
# life of the container, and this does the same until that reaches the release

{
  self.lib.test.testModules.notify =
    { lib, config, ... }:
    let
      cfg = config.toh.test.notify;
    in
    {
      options.toh.test.notify = {
        interval = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = ''
            Seconds between the looks at whether a container got a new notify
            socket, after it was killed and started again
          '';
        };
      };

      # NOTE: the drain only reads a socket once the driver cached the pid
      # of the init from it, and only while it is still the socket of the
      # machine, so it never takes the message a start waits for; a message
      # longer than what one read takes is cut, which is fine for one that
      # is thrown away
      config.toh.test.commands.helpers = lib.mkIf (config.toh.test.kind == "container") [
        ''
          import select as notify_select
          import threading as notify_threading
          import time as notify_time

          def notify_drain(machine):
            while True:
              socket = getattr(machine, "machine_sock", None)
              if socket is None or "get_systemd_process" not in machine.__dict__:
                notify_time.sleep(${builtins.toString cfg.interval})
                continue
              try:
                readable, _, _ = notify_select.select([socket], [], [], ${builtins.toString cfg.interval})
                while readable and machine.machine_sock is socket:
                  socket.recv(4096)
              except BlockingIOError:
                continue
              except (OSError, ValueError):
                notify_time.sleep(${builtins.toString cfg.interval})

          for notify_machine in machines:
            notify_threading.Thread(target=notify_drain, args=(notify_machine,), daemon=True).start()
        ''
      ];
    };
}
