#    This file was initially taken from Cricket, and reworked later
#
#    Copyright (C) 1998 Jeff R. Allen and WebTV Networks, Inc.
#    Copyright (C) 2002  Stanislav Sinyagin
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Stanislav Sinyagin <ssinyagin@k-open.com>


package Torrus::Log;

use strict;
use warnings;

use base 'Exporter';
use IO::Handle;
use Sys::Syslog qw(:standard :extended);

## no critic (Modules::ProhibitAutomaticExportation)

our @EXPORT = qw(Debug Warn Info Error Verbose isDebug);

my @monthNames = ( 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
                   'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );

my %logLevel =
    ( 'debug'    => 9,
      'verbose'  => 8,
      'info'     => 7,
      'warn'     => 5,
      'error'    => 1 );

my %syslogLevel =
    (9 => 'debug',
     8 => 'info',
     7 => 'notice',
     5 => 'warning',
     1 => 'err');
     
my $currentLogLevel = $logLevel{'info'};

*STDERR->autoflush();

# Thread ID
our $TID = 0;
sub setTID
{
    $TID = shift;
    return;
}


my $syslog_enabled = 0;

sub enableSyslog
{
    my $ident = shift;

    if( defined($Torrus::Log::syslogSockOpt) )
    {
        setlogsock(@{$Torrus::Log::syslogSockOpt});
    }
    
    openlog($ident, 'ndelay,pid', $Torrus::Log::syslogFacility);
    $syslog_enabled = 1;
    return;
}


END
{
    if( $syslog_enabled )
    {
        closelog();
    }
}


sub doLog
{
    my $level = shift;
    my @msg = @_;    

    if( $level <= $currentLogLevel )
    {
        if( $syslog_enabled )
        {
            syslog($syslogLevel{$level}, join('', @msg));
        }
        else
        {
            if( $currentLogLevel >= 9 )
            {
                unshift(@msg, $$ . '.' . $TID . ' ');
            }
        
            my $severity = ( $level <= 5 ) ? '*' : ' ';
            
            my $text = sprintf( "[%s%s] %s\n",
                                timeStr(time()),
                                $severity,
                                join('', @msg) );
            
            *STDERR->write($text, length($text));
        }
    }
    return;
}


sub Error
{
    doLog( 1, @_ );
    return;
}

sub Warn
{
    doLog( 5, @_);
    return;
}

sub Info
{
    doLog( 7, @_ );
    return;
}

sub Verbose
{
    doLog( 8, @_ );
    return;
}

sub Debug
{
    doLog( 9, join('|', @_) );
    return;
}


sub isDebug
{
    return ($currentLogLevel >= 9);
}

sub timeStr
{
    my $t = shift;
    
    my( $sec, $min, $hour, $mday, $mon, $year) = localtime( $t );
    
    return sprintf('%02d-%s-%04d %02d:%02d:%02d',
                   $mday, $monthNames[$mon], $year + 1900, $hour, $min, $sec);
}

sub setLevel
{
    my $level = lc( shift );

    if( defined( $logLevel{$level} ) )
    {
        $currentLogLevel = $logLevel{$level};
    }
    else
    {
        Error("Log level name '$level' unknown. Defaulting to 'info'");
        $currentLogLevel = $logLevel{'info'};
    }
    return;
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
