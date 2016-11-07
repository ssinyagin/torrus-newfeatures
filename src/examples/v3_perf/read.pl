use strict;
use warnings;
use JSON;
use IO::File;
use IO::Dir;

my $homedir = '/opt/t3/t/data/';

my $json = JSON->new;


my $d0 = IO::Dir->new($homedir) or die($!);

while( defined(my $dir0 = $d0->read()) )
{
    if( $dir0 =~ /^\w{2}$/ )
    {
        my $path1 = $homedir . '/' . $dir0;
        my $d1 = IO::Dir->new($path1) or die($!);

        while( defined(my $dir1 = $d1->read()) )
        {
            if( $dir1 =~ /^\w{2}$/ )
            {
                my $path2 = $path1 . '/' . $dir1;
                my $d2 = IO::Dir->new($path2) or die($!);

                while( defined(my $fname = $d2->read()) )
                {
                    if( $fname =~ /\w/ )
                    {
                        local $/;
                        my $filepath = $path2 . '/' . $fname;
                        my $fh = IO::File->new($filepath)
                            or die("Cannot open $filepath: $!");

                        my $data = $json->decode($fh->getline);
                        die("empty data") unless defined($data);
                        die("not a hash") unless ref($data) eq 'HASH';
                        
                        $fh->close;
                    }
                }
            }
        }
    }
}

