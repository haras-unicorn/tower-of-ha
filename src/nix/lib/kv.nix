{
  toh.lib.kv = {
    protocols = [
      "redis"
      "rediss"
    ];
    permissions = {
      all = "all";
      none = "none";
      health = "health";
      keyspace = "keyspace";
      read = "read";
      write = "write";
      set = "set";
      sortedset = "sortedset";
      list = "list";
      hash = "hash";
      string = "string";
      bitmap = "bitmap";
      hyperloglog = "hyperloglog";
      geo = "geo";
      stream = "stream";
      pubsub = "pubsub";
      admin = "admin";
      fast = "fast";
      slow = "slow";
      blocking = "blocking";
      dangerous = "dangerous";
      connection = "connection";
      transaction = "transaction";
      scripting = "scripting";
    };
  };
}
