##############################################
# $Id$
package main;

use strict;
use warnings;
use LWP::UserAgent;
use Time::Piece;

#####################################
sub
InfluxDBLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "InfluxDBLog_Define";
  $hash->{NotifyFn} = "InfluxDBLog_Log";
  $hash->{AttrFn}   = "InfluxDBLog_Attr";

  no warnings 'qw';
  my @attrList = qw(
      addStateEvent:1,0
          disable:1,0
          disabledForIntervals
      );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
}


#####################################
sub
InfluxDBLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $fh;

  return "wrong syntax: define <name> InfluxDBLog InfluxDBServer InfluxDBPort InfluxDatabase Username Password regexp"
      if(int(@a) != 8);

  return "Bad regexp: starting with *" if($a[5] =~ m/^\*/);
  eval { "Hallo" =~ m/^$a[5]$/ };
  return "Bad regexp: $@" if($@);

  $hash->{FH} = $fh;
  $hash->{REGEXP} = $a[7];
  $hash->{INFLUXSRV} = $a[2];
  $hash->{INFLUXPORT} = int($a[3]);
  $hash->{INFLUXDB} = $a[4];
  $hash->{INFLUXUSER} = $a[5];
  $hash->{INFLUXPW} = $a[6];
  $hash->{STATE} = "active";
  readingsSingleUpdate($hash, "filecount", 0, 0);
  notifyRegexpChanged($hash, $a[7]);
  Log3 $hash->{NAME}, 4, "$hash->{NAME}: Initialized";

  return undef;
}


#####################################
sub
InfluxDBLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;
  return if($log->{READONLY});
  Log3 $log->{NAME}, 4, "$log->{NAME}: Log";

  my $ln = $log->{NAME};
  Log3 $log->{NAME}, 4, "$log->{NAME}: 73";

  return if(IsDisabled($ln));
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events);

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$events});
  my $tn = $dev->{NTFY_TRIGGERTIME};
  my $ct = $dev->{CHANGETIME};

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {

      my %arg = (log=>$log, dev=>$dev, evt=>$s);

      InfluxDBLog_Write(\%arg);

    }
  }
  Log3 $log->{NAME}, 4, "$log->{NAME}: Log End";

  return "";
}

###################################
sub
InfluxDBLog_Write($)
{
  my ($ptr) = @_;
  my ($log, $dev, $EVENT) = ($ptr->{log}, $ptr->{dev}, $ptr->{evt});
  my $NAME = $dev->{NAME};

  my $ln = $log->{NAME};

  my @arr = split(": ", $EVENT);
  return if (int(@arr) != 2);

  my $data = "$arr[0],site_name=$NAME value=$arr[1]";

  Log3 $ln, 4, "$ln: Writing $data";

  my $uri = URI->new();

  $uri->scheme('http');
  $uri->host($log->{INFLUXSRV});
  $uri->port($log->{INFLUXPORT});
  $uri->path('write');
  $uri->query_form(db => $log->{INFLUXDB}, u => $log->{INFLUXUSER}, p=> $log->{INFLUXPW}) if (defined $log->{INFLUXDB});

  Log3 $ln, 4, "$ln: URI: $uri";
  my $lwp_user_agent = LWP::UserAgent->new();
  $lwp_user_agent->agent("FHEMInfluxDB-HTTP/0.01");
  my $response = $lwp_user_agent->post($uri->canonical(), Content => $data);

  if ($response->code() != 204) {
    my $error = $response->message();
    my $errorcode = $response->code();
    Log3 $ln, 4, "$ln: Error $errorcode $error";
  }

  return;

}

###################################
sub
InfluxDBLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

1;

=pod
=item helper
=item summary    write single events to a separate file each, using templates
=item summary_DE schreibt einzelne Events in separate Dateien via templates
=begin html

<a name="InfluxDBLog"></a>
<h3>InfluxDBLog</h3>
<ul>
  <br>

  <a name="InfluxDBLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; InfluxDBLog &lt;InfluxDBServer&gt; &lt;InfluxDBPort&gt; &lt;InfluxDatabase&gt; &lt;Username&gt; &lt;Password&gt; &lt;regexp&gt;
    </code>
    <br><br>
    Posts numeric Events to an InfluxDB instance.
  </ul>
  <br>

  <a name="InfluxDBLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li><br>

  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="InfluxDBLog"></a>
<h3>InfluxDBLog</h3>
<ul>
  <br>

  <a name="InfluxDBLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; InfluxDBLog &lt;InfluxDBServer&gt; &lt;InfluxDBPort&gt; &lt;InfluxDatabase&gt; &lt;Username&gt; &lt;Password&gt; &lt;regexp&gt;
    </code>
    <br><br>
    F&uuml; jedes Event oder Ger&auml;tename:Event, worauf &lt;regexp&gt;
    zutrifft, werden numerische Readings an die angegebene InfluxDB Instanz gesendet.
  </ul>
  <br>

  <a name="InfluxDBLogattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li><br>



  </ul>
  <br>
</ul>

=end html_DE

=cut
