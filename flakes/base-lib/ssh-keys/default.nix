rec {
  chris.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGaGrbXoVGe5fXpOhG6+pUZw+aYANuiDPvoI82jftpPd chris@thesogu.com";
  chris.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPflVyCskMX25z8S3pQLyGbo67zBQyC+eMbCkksRw4o/ chris@thesogu.com";
  chris.trap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO1u2+EqAzFOidZ+b0dixultkTyvIsOXZJsiG+/kDpJm chris@trap";
  chris.suremac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILz1u19VoCC/jj2lL34CmHwKAtIGt2clyMbZU8Cz4q14 chris.cummings@sureapp.com";
  system.thelio = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDOiCjIMganzY45qiHFEO2NqkXz2mWsSEmq3zIoRJsiA root@nixos";
  system.xps = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy30vzaxmqc08+NcYYA7LflDqoZNdRoyVXVJ2H9p2Xp root@xps-nixos";
  system.trap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNAyh1GNkiHi8eButk+acXT8E4LiKaLWq0jmJmQjwsk root@trap";
  usesRemoteBuilders = {
    inherit (system) thelio xps;
  };
}
