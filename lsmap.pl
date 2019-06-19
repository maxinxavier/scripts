#!c:\perl\bin\perl -w
# Author : MX
# Purpose : Report VTD to DISK relation 

my ( $VTD,$DISK );
open ( FILE1, "AP01.txt" ) or die "Could not open file :$!\n" ;
while (<FILE1>) {
    if( m/(VTD)\s+(\w+)/) {  
		chomp  ;  
		$VTD=$2 ;
	} ; 
    if( m/(Backing device)\s+(\w+)/ ) { 
		chomp ; 
		$DISK=$2 ;
	} ; 
    if ( m/^\s+$/){ 
		print "$DISK\t  $VTD \n" ;
	};
}
close (FILE1);
print "$DISK\t  $VTD \n" ;