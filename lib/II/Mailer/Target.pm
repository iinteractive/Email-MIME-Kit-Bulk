package II::Mailer::Target;
use Moose;
use namespace::autoclean;

use MooseX::Types::Email;

has to => (
    is       => 'ro',
    isa      => 'MooseX::Types::Email::EmailAddress',
    required => 1,
);

has cc => (
    traits  => ['Array'],
    isa     => 'ArrayRef[MooseX::Types::Email::EmailAddress]',
    default => sub { [] },
    handles => {
        cc => 'elements',
    },
);

has bcc => (
    traits  => ['Array'],
    isa     => 'ArrayRef[MooseX::Types::Email::EmailAddress]',
    default => sub { [] },
    handles => {
        bcc => 'elements',
    },
);

has from => (
    is  => 'ro',
    isa => 'MooseX::Types::Email::EmailAddress',
);

has template_params => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
);

sub recipients {
    my $self = shift;

    return (
        $self->to,
        $self->cc,
        $self->bcc,
    );
}

__PACKAGE__->meta->make_immutable;

1;
