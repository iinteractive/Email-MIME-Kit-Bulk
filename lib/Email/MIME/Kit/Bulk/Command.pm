package Email::MIME::Kit::Bulk::Command;
# ABSTRACT: send bulk emails using Email::MIME::Kit

=head1 SYNOPSIS

    use Email::MIME::Kit::Bulk::Command;

    Email::MIME::Kit::Bulk::Command->new_with_options->run;

=cut

use strict;
use warnings;

use MooseX::App::Simple;

use Email::MIME::Kit::Bulk;
use Email::MIME::Kit::Bulk::Target;
use JSON;
use MooseX::Types::Path::Tiny qw/ Path /;
use PerlX::Maybe;

option kit => (
    is       => 'ro',
    isa      => Path,
    required => 1,
    coerce   => 1,
    documentation => 'path to the mime kit directory',
);

option from => (
    is  => 'ro',
    isa => 'Str',
    documentation => 'sender address',
    required => 1,
);

option processes => (
    is  => 'ro',
    isa => 'Int',
    documentation => 'nbr of parallel processes for sending emails',
    default => 1,
);

option quiet => (
    is => 'ro',
    isa => 'Bool',
    documentation => q{don't output anything},
    default => 0,
);

has transport => (
    is => 'ro',
);

has _targets_file => (
    is      => 'ro',
    isa     => Path,
    lazy    => 1,
    default => sub { shift->kit->child('targets.json') },
);

sub BUILD {
    my $self = shift;

    die 'Kit directory must have a manifest'
        unless grep { -r }
               grep {
                   my $f = $_->basename;
                   $f =~ /^manifest\./ && $f =~ /\.json$/
               } $self->kit->children;

    die 'Cannot find target specification (' . $self->_targets_file . ')'
        unless -e $self->_targets_file;
}

sub run {
    my $self = shift;

    my @addresses = @{ decode_json($self->_targets_file->slurp) };

    my $mailer = Email::MIME::Kit::Bulk->new(
        verbose => !$self->quiet,
        targets => [ map { Email::MIME::Kit::Bulk::Target->new($_) } @addresses ],
        kit     => $self->kit,
        (defined $self->from
            ? (from => $self->from)
            : ()),
        (defined $self->processes
            ? (children => $self->processes)
            : ()),
        maybe transport => $self->transport,
    );

    $mailer->send;
}

__PACKAGE__->meta->make_immutable;

1;
