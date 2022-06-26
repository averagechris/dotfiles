{_, ...}: let
  socket = "/run/searx/searx.sock";
in {
  services.searx = {
    enable = true;
    runInUwsgi = true;
    uwsgiConfig = {
      inherit socket;
      disable-logging = true;
      cache2 = "name=searxcache,items=2000,blocks=2000,blocksize=4096,bitmap=1";
    };
    settings = {
      use_default_settings = true;
      server = {
        base_url = false;
        image_proxy = true;
        secret_key = "chris-test";
        # secret_key = "@SEARX_SECRET_KEY@";
      };
    };
  };
  services.nginx = {
    upstreams = {
      "searx" = {
        servers = {"unix://${socket}" = {};};
        extraConfig = ''
          include uwsgi_params;
        '';
      };
    };
  };
}
