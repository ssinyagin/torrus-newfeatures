#
#  Copyright (C) 2003  Christian Schnidrig
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# Christian Schnidrig <christian.schnidrig@bluewin.ch>


# Use a Perl plugin module as the collector source

package Torrus::Collector::Http;

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::RPN;

use strict;
use LWP::UserAgent;

# Register the collector type
$Torrus::Collector::collectorTypes{'http'} = 1;

###  Initialize the configuration validator with module-specific parameters

my %validatorLeafParams = (
   'http-object'         => undef,
   'http-url'            => undef,
   'http-timeout'        => undef,
  );

sub initValidatorLeafParams {
  my $hashref = shift;
  $hashref->{'ds-type'}{'collector'}{'collector-type'}{'http'} =
    \%validatorLeafParams;
}


# List of needed parameters and default values

$Torrus::Collector::params{'http'} = \%validatorLeafParams;

$Torrus::Collector::initTarget{'http'} = \&Torrus::Collector::Http::initTarget;

# initialize the user agent
$Torrus::Collector::Http::ua = LWP::UserAgent->new();
$Torrus::Collector::Http::ua->agent('Mozilla/5.0');

sub initTarget {
  my $collector = shift;
  my $token = shift;

  my $tref = $collector->tokenData( $token );
  my $cref = $collector->collectorData( 'http' );

  my $url = $collector->param( $token, 'http-url' );
  my $timeout = $collector->param( $token, 'http-timeout' );
  if (!defined($timeout)) { $timeout = 5;};
  if( not exists( $cref->{'byurl'}{$url} ) ) {
    $cref->{'byurl'}{$url} = [];
  }
  push( @{$cref->{'byurl'}{$url}}, $token );
  $cref->{'timeout'}{$url} = $timeout;

  return 1;
}

# This is first executed per target

$Torrus::Collector::runCollector{'http'} =
  \&Torrus::Collector::Http::runCollector;

sub runCollector {
  my $collector = shift;
  my $cref = shift;
  my $ua = $Torrus::Collector::Http::ua;

  my $now = time();

  foreach my $url (keys(%{$cref->{'byurl'}})) {
    Debug('Now doing '.$url, $cref->{timeout}{$url});
    $ua->timeout($cref->{timeout}{$url});
    my $res = $ua->get($url);

    if (!($res->is_success)) {
      Error('HTTP: Error getting: '.$url);
      foreach my $token (@{$cref->{'byurl'}{$url}}) {
        Debug("Setting value: U for token: $token");
        $collector->setValue( $token, 'U', $now );
      };
    } else {
      my $content = $res->content;
      #Debug ( "Web-Content:",$content );
      foreach my $token (@{$cref->{'byurl'}{$url}}) {

        my $object = $collector->param( $token, 'http-object' );

        # extract the values from the web page
        while ($object =~ /[,\s]*([\d*]+):\/([^,]*)\/\s*(?=,|$)/) {
          my $line = $1; my $pattern = $2;
          Debug ("Pattern: $line", $pattern);

          if ($line =~ /\d+/) {
            my @content = split(/\n\r*/, $content);
            Debug ('Line:', $content[$line-1]);
            my $value = 'UNKN';
            if ($content[$line-1] =~ $pattern) {
              $value = $1;
              Debug ("LineNumber: $line",
                     "Pattern: /$pattern/",
                     "Result: $value");
            } else {
              Error ("LineNumber: $line",
                     "Pattern: /$pattern/",
                     "No-Result!");
            };
            $object =~ s/[,\s]*[\d*]+:\/[^,]*\/\s*(?=,|$)/$value/;
          } else {
            my $value = 'UNKN';
            if ($content =~ $pattern) {
              $value = $1;
              Debug ("Pattern: /$pattern/",
                     "Result: $value");
            } else {
              Error ("Pattern: /$pattern/",
                     "No-Result!");
            };
            $object =~ s/[,\s]*[\d*]+:\/[^,]*\/\s*(?=,|$)/$value/;
          };
        };

        my $value;
        if ($object =~ /,/) {
          my $rpnObj = new Torrus::RPN;
          $value = $rpnObj->run($object, sub{} );
          if (!defined($value)) { $value = 'U'; }
        } else {
          if ($object eq 'UNKN') {
            $value = 'U';
          } else {
            $value = $object;
          };
        };

        Debug("Setting value: $value for token: $token");
        $collector->setValue( $token, $value, $now );
      }
    }
  }
};


1;

