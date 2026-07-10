rec {
  chris.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com";
  chris.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com";
  chris.trap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO1u2+EqAzFOidZ+b0dixultkTyvIsOXZJsiG+/kDpJm chris@trap";
  chris.suremac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILz1u19VoCC/jj2lL34CmHwKAtIGt2clyMbZU8Cz4q14 chris.cummings@sureapp.com";
  chris.srhtBuilds = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA5LSd9nCLfttzzbQ8iaoQo9Grd6CHSoNljFssffnnD/ srht-builds-thorny-builder";
  system.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
  system.tater = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBq8+MKDCaI81h80Q0xqch/jnJLaScTjpy0/LfpNQerv root@tater";
  system.suremac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhWkf9Nu/a8Nk0rdkCwzvYorYVItNP2oUuonQ2q5ri1 root@suremac";
  system.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos";
  system.trap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNAyh1GNkiHi8eButk+acXT8E4LiKaLWq0jmJmQjwsk root@trap";
  system.trainwreck = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICxXGUQ9Ey9/ndUJgr8ClI3PcnWYNnaY4kUMyHRrsYma root@trainwreck";
  usesRemoteBuilders = {
    inherit (chris) srhtBuilds suremac;
    inherit (system) tater thelio trainwreck trap xps;
  };
}
