# $Id$
#
# BioPerl module for Bio::DB::EUtilities
#
# Cared for by Chris Fields <cjfields at uiuc dot edu>
#
# Copyright Chris Fields
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code
#
# Interfaces with new GenericWebDBI interface

=head1 NAME

Bio::DB::GenericWebDBI - helper base class for parameter-based remote server
access and response retrieval.

=head1 SYNOPSIS

...

=head1 DESCRIPTION

WARNING: Please do B<NOT> spam the web servers with multiple requests.

...

=head1 TODO

...

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the
evolution of this and other Bioperl modules. Send
your comments and suggestions preferably to one
of the Bioperl mailing lists. Your participation
is much appreciated.

  bioperl-l@lists.open-bio.org               - General discussion
  http://www.bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to
help us keep track the bugs and their resolution.
Bug reports can be submitted via the web.

  http://bugzilla.open-bio.org/

=head1 AUTHOR

Email cjfields at uiuc dot edu

=head1 APPENDIX

The rest of the documentation details each of the
object methods. Internal methods are usually
preceded with a _

=cut

# Let the code begin...

package Bio::DB::GenericWebAgent;
use strict;
use warnings;
use base qw(Bio::Root::Root);
use LWP::UserAgent;

my $LAST_INVOCATION_TIME = 0;

=head2 new

 Title   : new
 Usage   : Bio::DB::GenericWebDBI->new(@args);
 Function: Create new Bio::DB::GenericWebDBI instance.
 Returns : 
 Args    : None specific to this base class.  Inheriting classes will
           likely set specific parameters in their constructor;
           Bio::DB::GenericWebDBI is primarily a test bed.

=cut

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    $self->ua(LWP::UserAgent->new(env_proxy => 1,
            agent => ref($self).':'.$self->VERSION));
    $self->delay($self->delay_policy);
    return $self;
}

=head1 GenericWebDBI methods

=head2 parameter_base

 Title   : parameter_base
 Usage   : $dbi->parameter_base($pobj);
 Function: Get/Set Bio::ParameterBaseI.
 Returns : Bio::ParameterBaseI object
 Args    : Bio::ParameterBaseI object

=cut

# this will likely be overridden in subclasses

sub parameter_base {
    my ($self, $pobj) = @_;
    if ($pobj) {
        $self->throw('Not a Bio::ParameterBaseI')
            if !$pobj->isa('Bio::ParameterBaseI');
        $self->{'_parameter_base'} = $pobj;
    }
    return $self->{'_parameter_base'};
}

=head2 ua

 Title   : ua
 Usage   : $dbi->ua;
 Function: Get/Set LWP::UserAgent.
 Returns : LWP::UserAgent
 Args    : LWP::UserAgent

=cut

sub ua {
	my ($self, $ua) = @_;
	if( defined $ua && $ua->isa("LWP::UserAgent") ) {
		$self->{'_ua'} = $ua;
	}
	return $self->{'_ua'};
}

=head2 get_Response

 Title   : get_Response
 Usage   : $agent->get_Response;
 Function: Get the HTTP::Response object by passing it an HTTP::Request (generated from
           Bio::ParameterBaseI implementation).
 Returns : HTTP::Response object or data if callback is used
 Args    : (optional)
 
           -cache_response - flag to cache HTTP::Response object; 
                             Default is 1 (TRUE, caching ON)
                             
           These are passed on to LWP::UserAgent::request() if stipulated
           
           -file   - use a LWP::UserAgent-compliant callback
           -cb     - dumps the response to a file (handy for large responses)
                     Note: can't use file and callback at the same time
           -read_size_hint - bytes of content to read in at a time to pass to callback
 Note    : Caching and parameter checking are set

=cut

sub get_Response {
    my ($self, @args) = @_;
    my ($cache, $file, $cb, $size) = $self->_rearrange([qw(CACHE_RESPONSE FILE CB READ_SIZE_HINT)],@args);
    $self->throw("Can't have both callback and file") if $file && $cb;
    # make -file accept more perl-like write-append type data.
    $file =~ s{^>}{} if $file; 
    my @opts = ($file || $cb, $size);
    $cache = (defined $cache && $cache == 0) ? 0 : 1;
    my $pobj = $self->parameter_base;
    if ($pobj->parameters_changed ||
        !$cache  ||
        !$self->{_response_cache}->content) {
        my $ua = $self->ua;
        $self->_sleep; # institute delay policy
        $self->throw('No parameter object set; cannot form a suitable remote request') unless $pobj;
        my $request = $pobj->to_request;
        if ($self->authentication) {
            $request->proxy_authorization_basic($self->authentication)
        }
        $self->debug("Request is: \n",$request->as_string);
        # I'm relying on the useragent to throw the proper errors here
        my $response = $ua->request($request,grep {defined $_} @opts);
        if ($response->is_error) {
            $self->throw("Response Error\n".$response->message);
        }
        $self->{_response_cache} = $response;
    } else {
        $self->debug("Returning cached HTTP::Response object\n");
    }
    return $self->{_response_cache};
}

=head2 get_Parser

 Title   : get_Parser
 Usage   : $agent->get_Parser;
 Function: Return HTTP::Response content (file, fh, object) attached to defined parser
 Returns : None
 Args    : None
 Note    : Abstract method; defined by implementation

=cut

sub get_Parser {
    shift->throw_not_implemented;
}

=head2 delay

 Title   : delay
 Usage   : $secs = $self->delay([$secs])
 Function: get/set number of seconds to delay between fetches
 Returns : number of seconds to delay
 Args    : new value

NOTE: the default is to use the value specified by delay_policy().
This can be overridden by calling this method.

=cut

sub delay {
   my $self = shift;
   return $self->{'_delay'} = shift if @_;
   return $self->{'_delay'};
}

=head2 delay_policy

 Title   : delay_policy
 Usage   : $secs = $self->delay_policy
 Function: return number of seconds to delay between calls to remote db
 Returns : number of seconds to delay
 Args    : none

NOTE: The default delay policy is 3s.  Override in subclasses to
implement delays.  The timer has only second resolution, so the delay
will actually be +/- 1s.

=cut

sub delay_policy {
   my $self = shift;
   return 3;
}

=head2 _sleep

 Title   : _sleep
 Usage   : $self->_sleep
 Function: sleep for a number of seconds indicated by the delay policy
 Returns : none
 Args    : none

NOTE: This method keeps track of the last time it was called and only
imposes a sleep if it was called more recently than the delay_policy()
allows.

=cut

sub _sleep {
   my $self = shift;
   my $last_invocation = $LAST_INVOCATION_TIME;
   if (time - $LAST_INVOCATION_TIME < $self->delay) {
      my $delay = $self->delay - (time - $LAST_INVOCATION_TIME);
      $self->debug("sleeping for $delay seconds\n");
      sleep $delay;
   }
   $LAST_INVOCATION_TIME = time;
}

=head1 LWP::UserAgent related methods

=head2 proxy

 Title   : proxy
 Usage   : $httpproxy = $db->proxy('http')  or
           $db->proxy(['http','ftp'], 'http://myproxy' )
 Function: Get/Set a proxy for use of proxy
 Returns : a string indicating the proxy
 Args    : $protocol : an array ref of the protocol(s) to set/get
           $proxyurl : url of the proxy to use for the specified protocol
           $username : username (if proxy requires authentication)
           $password : password (if proxy requires authentication)

=cut

sub proxy {
    my ($self,$protocol,$proxy,$username,$password) = @_;
    return undef if ( !defined $protocol || !defined $proxy );
    $self->authentication($username, $password)
    if ($username && $password);
    return $self->ua->proxy($protocol,$proxy);
}

=head2 authentication

 Title   : authentication
 Usage   : $db->authentication($user,$pass)
 Function: Get/Set authentication credentials
 Returns : Array of user/pass
 Args    : Array or user/pass

=cut

sub authentication{
   my ($self,$u,$p) = @_;
   if( defined $u && defined $p ) {
       $self->{'_authentication'} = [ $u,$p];
   }
   $self->{'_authentication'} && return @{$self->{'_authentication'}};
}

1;
