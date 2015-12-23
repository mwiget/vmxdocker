#!/usr/bin/perl
#

while(<>) {
  if ($_ =~ /^jlwaftr-(\w+)-(\w+)/) {
    if ($ifname1) {
      close OUT;
    }
    $ifname1 = $1;
    $ifname2 = $2;
    if ($ifname1 eq "" or $ifname2 eq "") {
      die "ifname1 or ifname2 not found in line $_";
    }
    $filename = "/tmp/$ifname1.sh";
    open(OUT, ">$filename") || die "Can't write to $filename!";
    print OUT "numactl --cpunodebind=\$1 --membind=\$1 \$2 snabbvmx run --conf snabbvmx-$ifname1.cfg --v6-pci `cat pci_$ifname1` --v4-pci `cat pci_$ifname2` --sock %s.socket\n";
    close OUT;

    $filename = "/tmp/$ifname2.sh";
    open(OUT, ">$filename") || die "Can't write to $filename!";
    print OUT <<EOF;
echo "port in use by snabbvmx snabbvmx-$ifname1.cfg ..."
sleep 30
EOF
    close OUT;

    open(IN,"mac_$ifname1") || die "Can't read from file mac_$ifname1";
    $mac1=<IN>; $mac1 =~ s/\n//g;
    close IN;
    open(IN,"mac_$ifname2") || die "Can't read from file mac_$ifname2";
    $mac2=<IN>; $mac2 =~ s/\n//g;
    close IN;

    $filename = "snabbvmx-$ifname1.cfg";
    open(OUT, ">$filename") || die "Can't write to $filename!";
    print OUT <<EOF;
return {
  {
    type = "jlwaftr",
EOF
  } elsif ($_ =~ /apply-macro (\w+)/) {
    if ("ipv4_interface" eq $type) {
      print OUT <<EOF;
      mac_address = "$mac2",
      port_id = "$ifname2",
    },
EOF
    }
    elsif ("ipv6_interface" eq $type) {
      print OUT <<EOF;
      mac_address = "$mac1",
      port_id = "$ifname1",
    },
EOF
    }
      elsif ($type) {
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
    if ($_ =~ /;/) {
    $value =~ s/;//;
    $key =~ s/;//;
#      print "key=$key, value=$value\n";
      if ($key =~ /:/)	{
         print OUT <<EOF;
      ["$key"] = "$value",
EOF
      } elsif ($value eq "") {
         print OUT <<EOF;
      $key = true;
EOF
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
}
EOF
