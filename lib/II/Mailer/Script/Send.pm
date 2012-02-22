package II::Mailer::Script::Send;
use Moose;
use namespace::autoclean;

use II::Mailer;
use II::Mailer::Target;
use JSON;
use MooseX::Types::Path::Class;
use Path::Class;

with 'MooseX::Getopt';

has kit => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
);

has from => (
    is  => 'ro',
    isa => 'Str',
);

has children => (
    is  => 'ro',
    isa => 'Int',
);

has _targets_file => (
    is      => 'ro',
    isa     => 'Path::Class::File',
    lazy    => 1,
    default => sub { shift->kit->file('targets.json') },
);

sub BUILD {
    my $self = shift;

    die 'Kit directory must have a manifest'
        unless -e $self->kit->file('manifest.json');
    die 'Cannot find target specification (' . $self->_targets_file . ')'
        unless -e $self->_targets_file;
}

sub run {
    my $self = shift;

    my @addresses = @{ decode_json($self->_targets_file->slurp) };

    my $mailer = II::Mailer->new(
        targets => [ map { II::Mailer::Target->new($_) } @addresses ],
        kit     => $self->kit,
        (defined $self->from
            ? (from => $self->from)
            : ()),
        (defined $self->children
            ? (children => $self->children)
            : ()),
    );

    $mailer->send;
}

__PACKAGE__->meta->make_immutable;

1;
