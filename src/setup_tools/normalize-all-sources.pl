#  Copyright (C) 2002  Stanislav Sinyagin
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Convert tabs to spaces and remove all extra space
# All files in current directories and subdirectories are processed,
# with all interesting extensions.

use File::Find;
use Text::Tabs;
use strict;

our @extensions = qw(ac css c html in pl pod pm xml);
our @exceptions = qw(Makefile.in normalize-all-sources.pl);

find( {wanted => \&process_file,
       preprocess =>  \&preprocess_filenames}, '.' );


sub preprocess_filenames
{
    my @names = @_;
    my @ret;
    for my $name ( @names )
    {
        if( $name ne 'CVS' )
        {
            push( @ret, $name );
        }
    }
    return( sort( @ret ) );
}

sub process_file
{
    my $filename = $_;
    if( -f $filename )
    {
        if( ( grep {$filename =~ /\.$_$/} @extensions ) and not
            ( grep {$filename eq $_} @exceptions ) )
        {
            printf STDERR ("Processing file: %s\n", $File::Find::name);

            open( IN, $filename ) or
                die('Error opening ' . $filename . ' for reading: ' . $!);
            my @lines = <IN>;
            close( IN );

            # Replace tabs with spaces
            @lines = expand( @lines );

            my $longLineReported = 0;
            my @new_lines = ();
            # Remove end-of-line space
            for my $line ( @lines )
            {
                $line =~ s/\s+$//;
                push( @new_lines, $line );
                if( length( $line ) > 80 and not $longLineReported )
                {
                    printf STDERR ("Line(s) longer than 80 symbols in %s\n",
                                   $File::Find::name);
                    $longLineReported = 1;
                }
            }
            @lines = @new_lines;
            @new_lines = ();

            # Remove empty lines at the beginning of the file
            while( scalar( @lines ) > 0 and $lines[0] =~ /^$/ )
            {
                splice( @lines, 0, 1 );
            }

            # Remove empty lines at the end of the file
            while( scalar( @lines ) > 0 and $lines[$#lines] =~ /^$/ )
            {
                splice( @lines, -1, 1 );
            }

            unlink( $filename ) or
                die('Error unlinking ' . $filename . ': ' . $!);

            open( OUT, "> $filename" ) or
                die('Error opening ' . $filename . ' for writing: ' . $!);
            for my $line ( @lines )
            {
                print OUT $line, "\n";
            }
            close( OUT );
        }
    }
}



# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
