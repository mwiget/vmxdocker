#!/usr/bin/perl
#
$mac_address = "44:44:44:44:44:44";
$vlan = "nil";

while(<>) {
  if ($_ =~ /^lwaftr-(\w+)/) {
    if ($ifname) {
      close OUT;
    }
    $ifname = $1;
    if ($ifname eq "") {
      die "ifname not found in line $_";
    }
    $filename = "/tmp/lwaftr-$ifname.cfg";
    $ifnumber = ($ifname =~ /(\d+)/) ? $1 : 0;
    $ifnumber = sprintf("%02d", $ifnumber);
#    print "ifnumber=$ifnumber\n";
   
    open(OUT, ">$filename") || die "Can't write to $filename!";
    print OUT <<EOF;
return {
  {
    port_id = "$ifname",
    ingress_filter = nil,
    gpbs = nil,
    tunnel = {
      type = "lwaftr",
EOF
  } elsif ($_ =~ /apply-macro (\w+)/) {
    if ($type) {
      print OUT <<EOF;
      },
EOF
    }
    $type = $1;
#    print "type=$type\n";
    print OUT <<EOF;
      $type = {
EOF
  } else {
    ($dummy, $key, $value) = split(/\s+/, $_);
    if ($value) {
      $value =~ s/;//;
#      print "key=$key, value=$value\n";
      if ($key =~ /:/)	{
         print OUT <<EOF;
         ["$key"] = "$value",
EOF
      } elsif ($key eq "mac_address") {
        # will be added at the end, outside of the tunnel stanza
        $mac_address = $value;
      } elsif ($key eq "vlan") {
        $vlan = $value;
      } else {
         print OUT <<EOF;
         $key = "$value",
EOF
      }

    }
    
  }
}
  print OUT <<EOF;
      },
    },
    vlan = $vlan,
    mac_address = "$mac_address",
  }
}
EOF
