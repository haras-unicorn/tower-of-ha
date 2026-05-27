{
  toh.lib.ldap = {
    permissions = rec {
      readOnly = "read-only";
      passwordChange = "password-change";

      keys = [
        "readOnly"
        "passwordChange"
      ];
      names = [
        readOnly
        passwordChange
      ];
    };
  };
}
