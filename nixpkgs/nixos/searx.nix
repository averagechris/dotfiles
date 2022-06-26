{_, ...}: {
  services.searx = {
    enable = true;
    runInUwsgi = true;
    uwsgiConfig = {
      disable-logging = true;
      http = ":8080";
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
}
