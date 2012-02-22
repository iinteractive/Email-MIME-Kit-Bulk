package II::Mailer;
use Moose;
use namespace::autoclean;
# ABSTRACT: Simple bulk mailer

use Email::MIME::Kit;
use Email::Sender::Simple 'sendmail';
use MooseX::Types::Email;
use MooseX::Types::Path::Class;
use Parallel::ForkManager;
use Try::Tiny;

use II::Mailer::Target;

has targets => (
    traits   => ['Array'],
    isa      => 'ArrayRef[II::Mailer::Target]',
    required => 1,
    handles  => {
        targets     => 'elements',
        num_targets => 'count',
    },
);

has kit => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
);

has from => (
    is      => 'ro',
    isa     => 'MooseX::Types::Email::EmailAddress',
    default => 'mailer@iinteractive.com',
);

has children => (
    is      => 'ro',
    isa     => 'Int',
    default => 5,
);

has fork_manager => (
    is      => 'ro',
    isa     => 'Parallel::ForkManager',
    lazy    => 1,
    default => sub { Parallel::ForkManager->new(shift->children) },
);

has mime_kit => (
    is      => 'ro',
    isa     => 'Email::MIME::Kit',
    lazy    => 1,
    default => sub {
        Email::MIME::Kit->new({ source => shift->kit->stringify })
    },
);

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    my $params = $class->$orig(@_);

    if (!exists $params->{targets} && exists $params->{to}) {
        $params->{targets} = [
            II::Mailer::Target->new(
                to => delete $params->{to},
                (exists $params->{cc}
                    ? (cc => delete $params->{cc})
                    : ()),
                (exists $params->{bcc}
                    ? (bcc => delete $params->{bcc})
                    : ()),
            )
        ];
    }

    return $params;
};

sub send {
    my $self = shift;

    my $pm = $self->fork_manager;

    my $errors;
    $pm->run_on_finish(sub {
        my (undef, $exit_code) = @_;
        $errors++ if $exit_code;
    });

    for my $target ($self->targets) {
        $pm->start and next;

        my $email = $self->assemble_mime_kit($target);
        my $res = try {
            sendmail(
                $email,
                {
                    from => $target->from,
                    to   => [ $target->recipients ],
                }
            );
            0;
        }
        catch {
            my @recipients = (blessed($_) && $_->isa('Email::Sender::Failure'))
                ? ($_->recipients)
                : ($target->recipients);

            # XXX better error handling here - logging?
            warn 'Failed to send to ' . join(', ', @recipients) . ': '
               . "$_";

            1;
        };

        $pm->finish($res);
    }

    $pm->wait_all_children;

    warn(($self->num_targets - $errors) . ' email(s) sent successfully'
       . ($errors ? " ($errors failure(s))" : ''));

    return $self->num_targets - $errors;
}

sub assemble_mime_kit {
    my $self = shift;
    my ($target) = @_;

    my $from = $target->from || $self->from;
    my $to   = $target->to;
    my @cc   = $target->cc;

    my $email = $self->mime_kit->assemble($target->template_params);

    $email->header_set('From' => $from)
        unless $email->header('From');
    $email->header_set('To' => $to)
        unless $email->header('To');
    $email->header_set('Cc' => join(', ', @cc))
        unless $email->header('Cc');

    return $email;
}

__PACKAGE__->meta->make_immutable;

1;
