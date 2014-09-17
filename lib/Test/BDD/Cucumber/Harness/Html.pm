package Test::BDD::Cucumber::Harness::Html;

use Moose;

# ABSTRACT: html output for Test::BDD::Cucumber
# VERSION

=head1 DESCRIPTION

A L<Test::BDD::Cucumber::Harness> subclass that generates html output.

=cut

use Time::HiRes qw ( time );
use Time::Piece;
use Sys::Hostname;
use Template;

use IO::File;
use IO::Handle;

extends 'Test::BDD::Cucumber::Harness::Data';

=head1 CONFIGURABLE ATTRIBUTES

=head2 fh

A filehandle to write output to; defaults to C<STDOUT>

=cut

has 'fh' => ( is => 'rw', isa => 'FileHandle', default => sub { \*STDOUT } );

has all_features => ( is => 'ro', isa => 'ArrayRef', default => sub { [] } );
has current_feature  => ( is => 'rw', isa => 'HashRef' );
has current_scenario => ( is => 'rw', isa => 'HashRef' );
has step_start_at    => ( is => 'rw', isa => 'Num' );

has 'template' => ( is => 'ro', isa => 'Template', lazy => 1,
	default => sub {
		my $self = shift;
                return Template->new(
                        ABSOLUTE => 1,
                        EVAL_PERL => 1,
                );
	},
);

has 'template_file' => ( is => 'rw', isa => 'Maybe[Str]' );
has 'template_content' => ( is => 'rw', isa => 'Str',
	default => sub {
		my $self = shift;
		my $c = '';
		my $h;
		if( defined $self->template_file ) {
			$h = IO::File->new($self->template_file, 'r')
				or die('error opening output template: '.$!);
		} else {
			$h = IO::Handle->new_from_fd(*DATA,'r')
				or die('error reading default template from __DATA__: '.$!);
		}
		while ( my $line = $h->getline ) {
			$c .= $line;
		}
		$h->close;
		return( $c );
	},
);

has title => ( is => 'rw', isa => 'Str', default => "Test Report");

sub feature {
    my ( $self, $feature ) = @_;
    $self->current_feature( $self->format_feature($feature) );
    push @{ $self->all_features }, $self->current_feature;
}

sub scenario {
    my ( $self, $scenario, $dataset ) = @_;
    $self->current_scenario( $self->format_scenario($scenario) );
    push @{ $self->current_feature->{elements} }, $self->current_scenario;
}

sub step {
    my ( $self, $context ) = @_;
    $self->step_start_at( time() );
}

sub step_done {
    my ( $self, $context, $result ) = @_;
    my $duration = time() - $self->step_start_at;
    my $step_data = $self->format_step( $context, $result, $duration );
    push @{ $self->current_scenario->{steps} }, $step_data;
}

sub shutdown {
    my ($self) = @_;
    my $html;
    my $template = $self->template_content;
    my $vars = {
	    'all_features' => $self->all_features,
	    'title' => $self->title,
	    'time' => Time::Piece->new(),
	    'hostname' => hostname(),
	    'command' => join(' ', $0, @ARGV),
    };
    $self->template->process( \$template, $vars, $self->fh )
        or die $self->template->error;
}

##################################
### Internal formating methods ###
##################################

sub get_keyword {
    my ( $self, $line_ref ) = @_;
    my ($keyword) = $line_ref->content =~ /^(\w+)/;
    return $keyword;
}

sub format_tags {
    my ( $self, $tags_ref ) = @_;
    return [ map { { name => '@' . $_ } } @$tags_ref ];
}

sub format_description {
    my ( $self, $feature ) = @_;
    return join "\n", map { $_->content } @{ $feature->satisfaction };
}

sub format_feature {
    my ( $self, $feature ) = @_;
    return {
        uri         => $feature->name_line->filename,
        keyword     => $self->get_keyword( $feature->name_line ),
        id          => "feature-" . int($feature),
        name        => $feature->name,
        line        => $feature->name_line->number,
        description => $self->format_description($feature),
        tags        => $self->format_tags( $feature->tags ),
        elements    => []
    };
}

sub format_scenario {
    my ( $self, $scenario, $dataset ) = @_;
    return {
        keyword => $self->get_keyword( $scenario->line ),
        id      => "scenario-" . int($scenario),
        name    => $scenario->name,
        line    => $scenario->line->number,
        tags    => $self->format_tags( $scenario->tags ),
        type    => $scenario->background ? 'background' : 'scenario',
        steps   => []
    };
}

sub format_step {
    my ( $self, $step_context, $result, $duration ) = @_;
    my $step = $step_context->step;
    return {
        keyword => $step ? $step->verb_original : $step_context->verb,
        name => $step_context->text,
        line => $step ? $step->line->number : 0,
        result => $self->format_result( $result, $duration )
    };
}

my %OUTPUT_STATUS = (
    passing   => 'passed',
    failing   => 'failed',
    pending   => 'pending',
    undefined => 'skipped',
);

sub format_result {
    my ( $self, $result, $duration ) = @_;
    return { status => "undefined" } if not $result;
    return {
        status        => $OUTPUT_STATUS{ $result->result },
        error_message => $result->output,
        defined $duration
        ? ( duration => int( $duration * 1_000_000_000 ) )
        : (),    # nanoseconds
    };
}

1;

__DATA__
[% BLOCK toc -%]
<ul>
[% FOREACH f = all_features -%]
  <li><a href="#[% f.id %]">[% f.name %]</a></li>
  <ul>
  [% FOREACH s = f.scenarios -%]
    <li><a href="#[% s.id %]">[% s.name %]</a></li>
  [% END -%]
  </ul>
[% END -%]
</ul>
[% END -%]
[% BLOCK scenario -%]
<h3 id="[% s.id %]">[% s.name %]</h3>
<table class="table step-table">
<thead><tr>
  <th class="step-name">Step</th>
  <th class="step-result">Result</th>
</tr></thead>
<tbody>
[% FOREACH step = s.steps -%]
[%
  IF step.result.status == 'passed';
    class = 'success';
  ELSIF  step.result.status == 'skipped';
    class = 'info';
  ELSIF  step.result.status == 'failed';
    class = 'danger';
  ELSIF  step.result.status == 'pending';
    class = 'warning';
  ELSE;
    class = '';
  END;
%]
<tr class="[% class %]">
	<td class="step-name"><b>[% step.keyword %]</b> [% step.name %]
          <div class="step-line">(line: [% step.line %])</div></td>
	<td class="step-result">[% step.result.status %]</td>
</tr> 
[% END -%]
</tbody>
</table>
[% END -%]
[% BLOCK feature -%]
<h2 id="[% f.id %]">[% f.name %] <small>([% f.uri %])</small></h2>
<p>[% f.description %]</p>
[% FOREACH scenario = f.scenarios -%]
    [% PROCESS scenario s=scenario -%]
[% END -%]
[% END -%]
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="[% title %]">

    <title>[% title %]</title>

    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css">
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js"></script>
    <style type="text/css">
    .step-table .step-name { text-align: left; }
    .step-table .step-result { text-align: right; }
    .step-table .step-line {
      color: grey;
      text-align: right;
      display: inline;
    }
    </style>
  </head>

  <body>
    <div class="container">

      <div class="page-header"><h1>[% title %]</h1></div>

      <h2>Document meta information</h2>
      <table class="table table-bordered">
      	<thead>
	  <th>Key</th>
	  <th>Value</th>
	</thead>
	<tbody>
	  <tr><td>Hostname</td><td>[% hostname %]</td></tr>
	  <tr><td>Time</td><td>[% time %]</td></tr>
	  <tr><td>Command</td><td>[% command %]</td></tr>
	</tbody>
      </table>

      <h2>Table of Content</h2>
[% PROCESS toc %]

[% FOREACH feature = all_features -%]
        [% PROCESS feature f=feature -%]
[% END -%]

    </div> <!-- /container -->
  </body>
</html>
