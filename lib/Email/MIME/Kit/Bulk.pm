package Email::MIME::Kit::Bulk;
# ABSTRACT: Email::MIME::Kit-based bulk mailer

$Email::MIME::Kit::Bulk::VERSION ||= '0.0';

=head1 SYNOPSIS

    use Email::MIME::Kit::Bulk;
    use Email::MIME::Kit::Bulk::Target;

    my @targets = (
        Email::MIME::Kit::Bulk::Target->new(
            to => 'someone@somewhere.com',
        ),
        Email::MIME::Kit::Bulk::Target->new(
            to => 'someone.else@somewhere.com',
            cc => 'copied@somewhere.com',
            language => 'en',
        ),
    );

    my $bulk = Email::MIME::Kit::Bulk->new(
        kit => '/path/to/mime/kit',
        processes => 5,
        targets => \@targets,
    );

    $bulk->send;

=head1 DESCRIPTION

C<Email::MIME::Kit::Bulk> is an extension of L<Email::MIME::Kit> for sending
bulk emails. The module can be used directly, or via the 
companion script C<emk_bulk>.

If a language is specified for a target, C<Email::MIME::Kit> will use
C<manifest.I<language>.json> to generate its associated email. If no language 
is given, the regular C<manifest.json> will be used instead.

If C<emk_bulk> is used, it'll look in the I<kit> directory for a
C<targets.json> file, which it'll use to create the email targets.
The format of the C<targets.json> file is a simple serialization of
the L<Email::MIME::Kit::Bulk::Target> constructor arguments:

    [
    {
        "to" : "someone@somewhere.com"
        "cc" : [
            "someone+cc@somewhere.com"
        ],
        "language" : "en",
        "template_params" : {
            "superlative" : "Fantastic"
        },
    },
    {
        "to" : "someone+french@somewhere.com"
        "cc" : [
            "someone+frenchcc@somewhere.com"
        ],
        "language" : "fr",
        "template_params" : {
            "superlative" : "Extraordinaire"
        },
    }
    ]


=cut

use Moose;
use namespace::autoclean;

use Email::MIME;
use Email::MIME::Kit;
use Email::Sender::Simple 'sendmail';
use MooseX::Types::Email;
use MooseX::Types::Path::Class;
use Parallel::ForkManager;
use Try::Tiny;
use PerlX::Maybe;

use Email::MIME::Kit::Bulk::Kit;
use Email::MIME::Kit::Bulk::Target;

=head1 METHODS

=head2 new( %args ) 

Constructor.

=head3 Arguments

=over

=item targets => \@targets

Takes in an array of L<Email::MIME::Kit::Bulk::Target> objects,
which are the email would-be recipients.

Either the argument C<targets> or C<to> must be passed to the constructor.

=item to => $email_address

Email address of the 'C<To:>' recipient. Ignored if C<targets> is given as well.

=item cc => $email_address

Email address of the 'C<Cc:>' recipient. Ignored if C<targets> is given as well.

=item bcc => $email_address

Email address of the 'C<Bcc:>' recipient. Ignored if C<targets> is given as well.

=back

=cut

has targets => (
    traits   => ['Array'],
    isa      => 'ArrayRef[Email::MIME::Kit::Bulk::Target]',
    required => 1,
    handles  => {
        targets     => 'elements',
        num_targets => 'count',
    },
);

=item kit => $path

Path of the directory holding the files used by L<Email::MIME::Kit>.

=cut

has kit => (
    is       => 'ro',
    isa      => 'Path::Class::Dir',
    required => 1,
    coerce   => 1,
);

=item from => $email_address

'C<From>' address for the email .

=cut

has from => (
    is       => 'ro',
    isa      => 'MooseX::Types::Email::EmailAddress',
    required => 1,
);

=item processes => $nbr

Maximal number of parallel processes used to send the emails.

Defaults to 1.

=cut

has processes => (
    is      => 'ro',
    isa     => 'Int',
    default => 1,
);

has fork_manager => (
    is      => 'ro',
    isa     => 'Parallel::ForkManager',
    lazy    => 1,
    default => sub { Parallel::ForkManager->new(shift->processes) },
);

has transport => (
    is => 'ro',
);

sub mime_kit {
    my $self = shift;
    Email::MIME::Kit::Bulk::Kit->new({
        source => $self->kit->stringify,
        @_,
    });
}

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;

    my $params = $class->$orig(@_);

    if (!exists $params->{targets} && exists $params->{to}) {
        $params->{targets} = [
            Email::MIME::Kit::Bulk::Target->new(
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

=head2 send()

Send the emails.

=cut

sub send {
    my $self = shift;

    my $pm = $self->fork_manager;

    my $af = STDOUT->autoflush;

    my $errors = 0;
    $pm->run_on_finish(sub {
        my (undef, $exit_code) = @_;
        $errors++ if $exit_code;
        print $exit_code ? "x" : ".";
    });

    for my $target ($self->targets) {
        $pm->start and next;

        my $email = $self->assemble_mime_kit($target);
        # work around bugs in q-p encoding (it forces \r\n, but the sendmail
        # executable expects \n, or something like that)
        (my $text = $email->as_string) =~ s/\x0d\x0a/\n/g;
        my $res = try {
            sendmail(
                $text,
                {
                    from => $target->from,
                    to   => [ $target->recipients ],
                    maybe transport => $self->transport,
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

    warn "\n" . ($self->num_targets - $errors) . ' email(s) sent successfully'
       . ($errors ? " ($errors failure(s))" : '') . "\n";

    STDOUT->autoflush($af);

    return $self->num_targets - $errors;
}

sub assemble_mime_kit {
    my $self = shift;
    my ($target) = @_;

    my $from = $target->from || $self->from;
    my $to   = $target->to;
    my @cc   = $target->cc;

    my %opts;
    $opts{language} = $target->language
        if $target->has_language;

    my $kit = $self->mime_kit(%opts);
    my $email = $kit->assemble($target->template_params);

    if (my @attachments = $target->extra_attachments) {
        my $old_email = $email;

        my @parts = map {
            my $attach = ref($_) ? $_ : [$_];
            Email::MIME->create(
                attributes => {
                    filename     => $attach->[0],
                    name         => $attach->[0],
                    encoding     => 'base64',
                    disposition  => 'attachment',
                    ($attach->[1]
                        ? (content_type => $attach->[1])
                        : ()),
                },
                body => ${ $kit->get_kit_entry($attach->[0]) },
            );
        } @attachments;

        $email = Email::MIME->create(
            header => [
                Subject => $old_email->header_obj->header_raw('Subject'),
            ],
            parts => [
                $old_email,
                @parts,
            ],
        );
    }

    # XXX Email::MIME::Kit reads the manifest.json file as latin1
    # fix this in a better way once that is fixed?
    my $subject = $email->header('Subject');
    utf8::decode($subject);
    $email->header_str_set('Subject' => $subject);

    $email->header_str_set('From' => $from)
        unless $email->header('From');
    $email->header_str_set('To' => $to)
        unless $email->header('To');
    $email->header_str_set('Cc' => join(', ', @cc))
        unless $email->header('Cc') || !@cc;

    $email->header_str_set(
        'X-UserAgent' 
            => "Email::MIME::Kit::Bulk v$Email::MIME::Kit::Bulk::VERSION"
    );

    return $email;
}

__PACKAGE__->meta->make_immutable;

1;
