#!/usr/bin/env perl

=head1 NAME

ebeye_lwp.pl

=head1 DESCRIPTION

EBI Search (REST) web service Perl client using L<LWP>.

Tested with:

=over

=item *
L<LWP> 5.79, L<XML::Simple> 2.12 and Perl 5.8.3

=item *
L<LWP> 5.808, L<XML::Simple> 2.18 and Perl 5.8.8 (Ubuntu 8.04 LTS)

=item *
L<LWP> 5.834, L<XML::Simple> 2.18 and Perl 5.10.1 (Ubuntu 10.04 LTS)

=item *
L<LWP> 6.03, L<XML::Simple> 2.18 and Perl 5.14.2 (Ubuntu 12.04 LTS)

=back

For further information see:

=over

=item *
L<http://www.ebi.ac.uk/Tools/webservices/services/eb-eye>

=item *
L<http://www.ebi.ac.uk/Tools/webservices/tutorials/perl>

=back

=head1 LICENSE

Copyright 2012-2014 EMBL - European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 VERSION

$Id: fastm_lwp.pl 2702 2014-01-16 13:50:03Z hpm $

=cut

# ======================================================================
# Enable Perl warnings
use strict;
use warnings;

# Load libraries
use English;
use LWP;
use XML::Simple;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename;
use Data::Dumper;

# Base URL for service
my $baseUrl = 'http://wwwdev.ebi.ac.uk/ebisearch/ws/rest';

# Output level
my $outputLevel = 1;

# Process command-line options
my $numOpts = scalar(@ARGV);
my %params = ( 'debugLevel' => 0 );


# Default parameter values (should get these from the service)
GetOptions(
	'quiet'        => \$params{'quiet'},         # Decrease output level
	'verbose'      => \$params{'verbose'},       # Increase output level
	'debugLevel=i' => \$params{'debugLevel'},    # Debug output level
	'baseUrl=s'    => \$baseUrl,                 # Base URL for service.
);
if ( $params{'verbose'} ) { $outputLevel++ }
if ( $params{'$quiet'} )  { $outputLevel-- }

# Debug mode: LWP version
&print_debug_message( 'MAIN', 'LWP::VERSION: ' . $LWP::VERSION,	1 );

# Debug mode: print the input parameters
&print_debug_message( 'MAIN', "params:\n" . Dumper( \%params ), 11 );

# LWP UserAgent for making HTTP calls (initialised when required).
my $ua;

# Get the script filename for use in usage messages
my $scriptName = basename( $0, () );

# Print usage and exit if requested
if ( $params{'help'} || $numOpts == 0 ) {
	&usage();
	exit(0);
}

# Debug mode: show the base URL
&print_debug_message( 'MAIN', 'baseUrl: ' . $baseUrl, 1 );

my $method = shift;

# Get domain hierarchy
if ( $method eq 'getDomainHierarchy' ) {
	&print_get_domain_hierarchy();
}

# Get domain details
elsif ( $method eq 'getDomainDetails' ) {
	&print_get_domain_details(@ARGV);
}

# Get search results
elsif ( $method eq 'getResults') {
	&print_get_results(@ARGV);
}

# Get search results with facets
elsif ( $method eq 'getFacetedResults') {
	&print_get_faceted_results(@ARGV);
}

# Get entries
elsif ( $method eq 'getEntries') {
	&print_get_entries(@ARGV);
}

# Get domain ids referenced in a domain
elsif ( $method eq 'getDomainsReferencedInDomain') {
	&print_get_domains_referenced_in_domain(@ARGV);
}

# Get domain ids referenced in an entry
elsif ( $method eq 'getDomainsReferencedInEntry') {
	&print_get_domains_referenced_in_entry(@ARGV);	
}

# Get cross references
elsif ( $method eq 'getReferencedEntries') {
	&print_get_referenced_entries(@ARGV);
}
else {
	&usage();
	exit(1);
}

=head1 FUNCTIONS

=cut

### Wrappers for REST resources ###

=head2 rest_user_agent()

Get a LWP UserAgent to use to perform REST requests.

  my $ua = &rest_user_agent();

=cut

sub rest_user_agent() {
	print_debug_message( 'rest_user_agent', 'Begin', 21 );
	# Create an LWP UserAgent for making HTTP calls.
	my $ua = LWP::UserAgent->new();
	# Set 'User-Agent' HTTP header to identifiy the client.
	my $revisionNumber = 0;	
	$revisionNumber = $1 if('$Revision: 2702 $' =~ m/(\d+)/);	
	$ua->agent("EBI-Sample-Client/$revisionNumber ($scriptName; $OSNAME) " . $ua->agent());
	# Configure HTTP proxy support from environment.
	$ua->env_proxy;
	print_debug_message( 'rest_user_agent', 'End', 21 );
	return $ua;
}

=head2 rest_error()

Check a REST response for an error condition. An error is mapped to a die.

  &rest_error($response, $content_data);

=cut

sub rest_error() {
	print_debug_message( 'rest_error', 'Begin', 21 );
	my $response = shift;
	my $contentdata;
	if(scalar(@_) > 0) {
		$contentdata = shift;
	}
	if(!defined($contentdata) || $contentdata eq '') {
		$contentdata = $response->content();
	}
	# Check for HTTP error codes
	if ( $response->is_error ) {
		my $error_message = '';
		# HTML response.
		if(	$contentdata =~ m/<h1>([^<]+)<\/h1>/ ) {
			$error_message = $1;
		}
		#  XML response.
		elsif($contentdata =~ m/<description>([^<]+)<\/description>/) {
			$error_message = $1;
		}
		die 'http status: ' . $response->code . ' ' . $response->message . '  ' . $error_message;
	}
	print_debug_message( 'rest_error', 'End', 21 );
}

=head2 rest_request()

Perform a REST request (HTTP GET).

  my $response_str = &rest_request($url);

=cut

sub rest_request {
	print_debug_message( 'rest_request', 'Begin', 11 );
	my $requestUrl = shift;
	print_debug_message( 'rest_request', 'URL: ' . $requestUrl, 11 );

	# Get an LWP UserAgent.
	$ua = &rest_user_agent() unless defined($ua);
	# Available HTTP compression methods.
	my $can_accept;
	eval {
	    $can_accept = HTTP::Message::decodable();
	};
	$can_accept = '' unless defined($can_accept);
	# Perform the request
	my $response = $ua->get($requestUrl,
		'Accept-Encoding' => $can_accept, # HTTP compression.
	);
	print_debug_message( 'rest_request', 'HTTP status: ' . $response->code, 11 );
	print_debug_message( 'rest_request', 'response length: ' . length($response->content()), 11 );
	print_debug_message( 'rest_request', 'request:' ."\n" . $response->request()->as_string(), 32 );
	print_debug_message( 'rest_request', 'response: ' . "\n" . $response->as_string(), 32 );
	# Unpack possibly compressed response.
	my $retVal;
	if ( defined($can_accept) && $can_accept ne '') {
	    $retVal = $response->decoded_content();
	}
	# If unable to decode use orginal content.
	$retVal = $response->content() unless defined($retVal);
	# Check for an error.
	&rest_error($response, $retVal);
	print_debug_message( 'rest_request', 'retVal: ' . $retVal, 12 );
	print_debug_message( 'rest_request', 'End', 11 );

	# Return the response data
	return $retVal;
}

=head2

Print domain hierarchy

  &print_get_domain_hierarchy();

=cut

sub print_get_domain_hierarchy {
	print_debug_message( 'print_get_domain_hierarchy', 'Begin', 11 );
	my ($param_list_xml) = &rest_get_domain_hierarchy();
	&_print_domains($param_list_xml->{domains}->{domain}, "");
	print_debug_message( 'print_get_domain_hierarchy', 'End', 11 );
}

sub _print_domains{
	my ($domain, $indent) = @_;
	print $indent . $domain->{'id'} . ": " . $domain->{'name'}, "\n";
	if (exists $domain->{'subdomains'}) {
		my $subdomains = $domain->{'subdomains'}->{'domain'};
		if(ref($subdomains) eq 'ARRAY'){
			foreach my $subdomain (@{$subdomains}) {
				&_print_domains($subdomain, $indent ."\t");
			}
		}
		else {
			&_print_domains($subdomains, $indent ."\t");
		}
	}
}

=head2

Print domain details

  &print_get_domain_details($domainid);

=cut

sub print_get_domain_details {
	print_debug_message( 'print_get_domain_details', 'Begin', 1 );
	my ($param_list_xml) = &rest_get_domain_details(@_);
	&_print_domain_details($param_list_xml->{'domains'}->{'domain'});
	print_debug_message( 'print_get_domain_details', 'End', 1 );
}

sub _print_domain_details{
	my ($domain) = @_;
	print $domain->{'name'} . " (" .$domain->{'id'} . ")", "\n";
	if (exists $domain->{'subdomains'}) {
		my $subdomains = $domain->{'subdomains'}->{'domain'};
		if(ref($subdomains) eq 'ARRAY'){
			foreach my $subdomain (@{$subdomains}) {
				&_print_domain_details($subdomain);
			}
		}
		else {
			&_print_domain_details($subdomains);
		}
	}
	else {
		my $indexInfos = $domain->{'indexInfos'}->{'indexInfo'};
		foreach my $indexInfo (@{$indexInfos}) {
			print $indexInfo->{'name'} . ": " . $indexInfo->{'content'}, "\n";
		}
		print "\n";
		my $fieldInfos = $domain->{'fieldInfos'}->{'fieldInfo'};
		print "field_id\tsearchable\tretrievable\tsortable\tfacet", "\n";
		foreach my $fieldInfo (@{$fieldInfos}) {
			print $fieldInfo->{'id'} . "\t";
			foreach my $option (@{$fieldInfo->{'options'}->{'option'}}) {
				print $option->{'content'} . "\t";
			}
			print "\n";
		}
	}
	print "\n";
}

=head2

Print search results

  &print_get_results($domainid, $query, $fields, $size, $start, $fieldurl, $viewurl, $sortfield, $order);

=cut

sub print_get_results {
	print_debug_message( 'print_get_results', 'Begin', 1 );
	my ($param_list_xml) = &rest_get_results(@_);
	&_print_entries($param_list_xml->{'entries'}->{'entry'});
	print_debug_message( 'print_get_results', 'End', 1 );
}

sub _print_entries {
	my $entries = shift;
	print_debug_message( '_print_enties', 'len($entires)=' . scalar(@{$entries}) ,1);
	foreach my $entry (@{$entries}) {
		foreach my $field (@{$entry->{'fields'}->{'field'}}) {
			if (exists $field->{'values'}->{'value'}) {
				foreach my $value (@{$field->{'values'}->{'value'}}) {
					print $value, "\n";
				}
			}
			else {
				print "\n";
			}
		}

		foreach my $fieldurl (@{$entry->{'fieldURLs'}->{'fieldURL'}}) {
			print $fieldurl, "\n";
		}

		foreach my $viewurl (@{$entry->{'viewURLs'}->{'viewURL'}}) {
			print $viewurl->{'content'}, "\n";
		}
		print "\n";
	}	
}

=head2

Print search results with facets

  &print_get_faceted_results($domainid, $query, $fields, $size, $start, $fieldurl, $viewurl, $sortfield, $order, $facetcount, $facetfields);

=cut

sub print_get_faceted_results {
	print_debug_message( 'print_get_faceted_results', 'Begin', 1 );
	my ($param_list_xml) = &rest_get_faceted_results(@_);
	&_print_entries($param_list_xml->{'entries'}->{'entry'});
	&_print_facets($param_list_xml->{'facets'}->{'facet'});
	print_debug_message( 'print_get_faceted_results', 'End', 1 );
}


sub _print_facets {
	my $facets = shift;
	
	foreach my $facet (@{$facets}) {
		print $facet->{'label'} . " (" .$facet->{'id'} . ") ", "\n";
		foreach my $facetValue (@{$facet->{'facetValues'}->{'facetValue'}}) {
			print $facetValue->{'label'} . " (" . $facetValue->{'value'}->[0] . ") " . $facetValue->{'count'}, "\n";
		}

		print "\n";
	}	
}

=head2

Print entries

  &print_get_entries($domainid, $entryid, $fields, $fieldurl, $viewurl);

=cut

sub print_get_entries {
	print_debug_message( 'print_get_entries', 'Begin', 1 );
	my ($param_list_xml) = &rest_get_entries(@_);
	&_print_entries($param_list_xml->{'entries'}->{'entry'});
	print_debug_message( 'print_get_entries', 'End', 1 );
}



=head2

Print domain ids referenced in a domain

  &print_get_domains_referenced_in_domain($domainid);

=cut

sub print_get_domains_referenced_in_domain {
	print_debug_message( 'print_get_domains_referenced_in_domain', 'Begin', 1 );
	my ($domain_list) = &rest_get_domains_referenced_in_domain(@_);
	foreach my $domain (@{$domain_list->{'domains'}->{'domain'}}){
		print $domain->{'id'}, "\n";
	} 
	print_debug_message( 'print_get_domains_referenced_in_domain', 'End', 1 );
}


=head2

Print domain ids referenced in an entry

  &print_get_domains_referenced_in_entry($domainid, $entryid);

=cut

sub print_get_domains_referenced_in_entry {
	print_debug_message( 'print_get_domains_referenced_in_entry', 'Begin', 1 );
	my ($domain_list) = &rest_get_domains_referenced_in_entry(@_);
	foreach my $domain (@{$domain_list->{'domains'}->{'domain'}}){
		print $domain->{'id'}, "\n";
	} 
	print_debug_message( 'print_get_domains_referenced_in_entry', 'End', 1 );
}


=head2

Print cross references

  &print_get_referenced_entries($domainid, $entryid, $referencedDomainId, $fields, $size, $start, $fieldurl, $viewurl);

=cut

sub print_get_referenced_entries {
	print_debug_message( 'print_get_referenced_entries', 'Begin', 1 );
	my ($param_list_xml) = &rest_get_referenced_entries(@_);
	foreach my $entry (@{$param_list_xml->{'entries'}->{'entry'}}) {
		&_print_entries($entry->{'references'}->{'reference'});
	}
	print_debug_message( 'print_get_referenced_entries', 'End', 1 );
}




=head2 rest_get_domain_hierarchy()

Get domain hierarchy

  my ($param_list_xml) = &rest_get_domain_hierarchy();

=cut

sub rest_get_domain_hierarchy {
	print_debug_message( 'rest_get_domain_hierarchy', 'Begin', 1 );
	my $url                = $baseUrl;
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_domain_hierarchy', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => []);
}


=head2 rest_get_domain_details()

Get domain details

  my ($param_list_xml) = &rest_get_domain_details($domainid);

=cut

sub rest_get_domain_details {
	print_debug_message( 'rest_get_domain_details', 'Begin', 1 );
	my $domainid = shift || 'allebi';
	my $url                = $baseUrl . "/" .$domainid;
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_domain_details', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => []);
}


=head2 rest_get_results()

Get search results

  my ($param_list_xml) = &rest_get_results($domainid, $query, $fields, $size, $start, $fieldurl, $viewurl, $sortfield, $order);

=cut

sub rest_get_results {
	print_debug_message( 'rest_get_results', 'Begin', 1 );
	my $domainid = shift;
	my $query = shift;
	my $fields = "";
	$fields = shift if ( scalar(@_) > 0 );
	my $size = "";
	$size = shift if ( scalar(@_) > 0 );
	my $start = "";
	$start = shift if ( scalar(@_) > 0 );
	my $fieldurl = "";
	$fieldurl = shift if ( scalar(@_) > 0 );
	my $viewurl = "";
	$viewurl =shift if ( scalar(@_) > 0 );
	my $sortfield = "";
	$sortfield = shift if ( scalar(@_) > 0 );
	my $order = "";
	$order = shift if ( scalar(@_) > 0 );

	my $url = $baseUrl . "/" .$domainid . "?query=" . $query . "&fields=" .$fields . "&size=" . $size ."&start=" . $start. "&viewurl=" . $viewurl . "&fieldurl=".$fieldurl . "&sortfield=". $sortfield . "&order=". $order ."&facetcount=0";
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_results', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['entry', 'value', 'field', 'fieldURL', 'viewURL']);
}

=head2 rest_get_faceted_results()

Get search results with facets

  my ($param_list_xml) = &rest_get_faceted_results($domainid, $query, $fields, $size, $start, $fieldurl, $viewurl, $sortfield, $order, $facetcount, $facetfields);

=cut

sub rest_get_faceted_results {
	print_debug_message( 'rest_get_faceted_results', 'Begin', 1 );
	my $domainid = shift;
	my $query = shift;
	my $fields = "";
	$fields = shift if ( scalar(@_) > 0 );
	my $size = "";
	$size = shift if ( scalar(@_) > 0 );
	my $start = "";
	$start = shift if ( scalar(@_) > 0 );
	my $fieldurl = "";
	$fieldurl = shift if ( scalar(@_) > 0 );
	my $viewurl = "";
	$viewurl =shift if ( scalar(@_) > 0 );
	my $sortfield = "";
	$sortfield = shift if ( scalar(@_) > 0 );
	my $order = "";
	$order = shift if ( scalar(@_) > 0 );
	my $facetcount = "10";
	$facetcount = shift if ( scalar(@_) > 0 );
	my $facetfields = "";
	$facetfields = shift if ( scalar(@_) > 0 );
	my $url                = $baseUrl . "/" .$domainid . "?query=" . $query . "&fields=" .$fields . "&size=" . $size ."&start=" . $start. "&viewurl=" . $viewurl . "&fieldurl=".$fieldurl . "&sortfield=". $sortfield . "&order=". $order . "&facetcount=".$facetcount ."&facetfields=". $facetfields;
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_faceted_results', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['entry', 'value', 'field', 'fieldURL', 'viewURL', 'facet', 'facetValue']);
}

=head2 rest_get_entries()

Get entries

  my ($param_list_xml) = &rest_get_entries($domainid, $entryid, $fields, $fieldurl, $viewurl);

=cut

sub rest_get_entries {
	print_debug_message( 'rest_get_entries', 'Begin', 1 );
	my $domainid = shift;
	my $entryid = shift;
	my $fields = "";
	$fields = shift if ( scalar(@_) > 0 );
	my $fieldurl = "";
	$fieldurl = shift if ( scalar(@_) > 0 );
	my $viewurl = "";
	$viewurl =shift if ( scalar(@_) > 0 );
	my $url                = $baseUrl . "/" .$domainid . "/entry/" . $entryid . "?fields=" .$fields . "&viewurl=" . $viewurl . "&fieldurl=".$fieldurl;
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_entries', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['entry', 'value', 'field', 'fieldURL', 'viewURL']);
}



=head2 rest_get_domains_referenced_in_domain()

Get domain ids referenced in a domain

  my ($param_list_xml) = &rest_get_domains_referenced_in_domain($domainid);

=cut

sub rest_get_domains_referenced_in_domain {
	print_debug_message( 'rest_get_domains_referenced_in_domain', 'Begin', 1 );
	my ($domainid) = @_;
	my $url                = $baseUrl . "/" .$domainid . "/xref";
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_domains_referenced_in_domain', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['domain']);
}


=head2 rest_get_domains_referenced_in_entry()

Get domain ids referenced in an entry

  my ($param_list_xml) = &rest_get_domains_referenced_in_entry($domainid, $entryid);

=cut

sub rest_get_domains_referenced_in_entry {
	print_debug_message( 'rest_get_domains_referenced_in_entry', 'Begin', 1 );
	my ($domainid, $entryid) = @_;
	my $url                = $baseUrl . "/" .$domainid . "/entry/" . $entryid ."/xref/";
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_domains_referenced_in_entry', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['entry', 'reference', 'value', 'field', 'fieldURL', 'viewURL']);
}


=head2 rest_get_referenced_entries()

Get cross references

  my (@domain_list) = &rest_get_referenced_entries($domainid, $entryids, $referencedDomainId, $fields, $size, $start, $fieldurl, $viewurl);

=cut

sub rest_get_referenced_entries {
	print_debug_message( 'rest_get_referenced_entries', 'Begin', 1 );
	my $domainid = shift;
	my $entryids = shift;
	my $referencedDomainId = shift;
	my $fields = "";
	$fields = shift if ( scalar(@_) > 0 );
	my $size = "";
	$size = shift if ( scalar(@_) > 0 );
	my $start = "";
	$start = shift if ( scalar(@_) > 0 );
	my $fieldurl = "";
	$fieldurl = shift if ( scalar(@_) > 0 );
	my $viewurl = "";
	$viewurl =shift if ( scalar(@_) > 0 );
	my $url                = $baseUrl . "/" .$domainid . "/entry/" . $entryids ."/xref/" . $referencedDomainId . "?fields=" .$fields . "&start=" . $start. "&size=" . $size. "&fieldurl=".$fieldurl . "&viewurl=".$viewurl;
	my $param_list_xml_str = &rest_request($url);
	print_debug_message( 'rest_get_referenced_entries', 'End', 1 );
	return XMLin($param_list_xml_str, KeyAttr => [], ForceArray => ['entry', 'reference', 'value', 'field', 'fieldURL', 'viewURL']);
}


### Service actions and utility functions ###

=head2 print_debug_message()

Print debug message at specified debug level.

  &print_debug_message($method_name, $message, $level);

=cut

sub print_debug_message {
	my $function_name = shift;
	my $message       = shift;
	my $level         = shift;
	if ( $level <= $params{'debugLevel'} ) {
		print STDERR '[', $function_name, '()] ', $message, "\n";
	}
}

=head2 usage()

Print program usage message.

  &usage();

=cut

sub usage {
	print STDERR <<EOF
EB-eye
======

Usage:
  ebeye_lwp.pl <method> [arguments...] [--baseUrl <baseUrl>]

A number of methods are available:

getDomainHierarchy
  Return the hierarchy of the domains availabe.
  
getDomainDetails [<domain>]
  Return the details of a particula domain.

getResults <domain> <query> <fields> [<size> [<start> [<fieldurl> [<viewurl> [<sortfield> [<order>]]]]]]
  Executes a query and returns a list of results.
  
getFacetedResults <domain> <query> [<fields> [<size> [<start> [<fieldurl> [<viewurl> [<sortfield> [<order> [<facetcount> [<facetfields>]]]]]]]]]
  Executes a query and returns a list of results including facets.

getEntries <domain> <entryids> <fields> [<fieldurl> [<viewurl>]]
  Search for entries in a domain and returns the values for some of the 
  fields of these entries.

getDomainsReferencedInDomain <domain>
  Returns the list of domains with entries referenced in a particular domain. 
  These domains are indexed in the EB-eye. 

getDomainsReferencedInEntry <domain> <entryid>
  Returns the list of domains with entries referenced in a particular domain 
  entry. These domains are indexed in the EB-eye.

getReferencedEntries <domain> <entryids> <referencedDomain> <fields> [<size> [<start> [<fieldurl> [<viewurl>]]]
  Returns the list of referenced entry identifiers from a domain referenced 
  in a particular domain entry. 

Support/Feedback:

  http://www.ebi.ac.uk/support/
EOF
}

=head1 FEEDBACK/SUPPORT

Please contact us at L<http://www.ebi.ac.uk/support/> if you have any 
feedback, suggestions or issues with the service or this client.

=cut
