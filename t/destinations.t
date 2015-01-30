use strict;
use warnings;

use Test::More tests => 3;

use Email::MIME::Kit::Bulk::Command;
use Email::Sender::Transport::Maildir;
use Path::Tiny qw/ tempdir /;

use Test::Email;

$Email::MIME::Kit::Bulk::VERSION ||= "0.0";

my $maildir = tempdir();

# the forking makes using EST::Test difficult
my $transport = Email::Sender::Transport::Maildir->new( dir => $maildir );

my %args = ( 
    kit  => 'examples/eg.mkit',
    from => 'me@here.com',
    transport => $transport,
    quiet => 1,
    targets => [],
);

my $bulk = Email::MIME::Kit::Bulk->new(
    %args,
);

subtest "specify everything" => sub {
    my $target = Email::MIME::Kit::Bulk::Target->new(
        from => 'me@foo.com',
        to => 'one@foo.com',
        cc => [ 'two@foo.com', 'three@foo.com' ],
        bcc => [ 'three@foo.com', 'four@foo.com' ],
        language => 'en',
        template_params => {
            superlative => 'Wicked',
        },
    );

    my $email = $bulk->assemble_mime_kit( $target );

    is $email->header('From') => 'me@foo.com', 'from';
    is $email->header('To') => 'one@foo.com', 'to';
    is $email->header('Cc') => 'two@foo.com, three@foo.com', 'cc';
};

subtest "no from" => sub {
    my $target = Email::MIME::Kit::Bulk::Target->new(
        to => 'one@foo.com',
        cc => [ 'two@foo.com', 'three@foo.com' ],
        bcc => [ 'three@foo.com', 'four@foo.com' ],
        language => 'en',
        template_params => {
            superlative => 'Wicked',
        },
    );

    my $email = $bulk->assemble_mime_kit( $target );

    is $email->header('From') => 'me@here.com', 'from';
    is $email->header('To') => 'one@foo.com', 'to';
    is $email->header('Cc') => 'two@foo.com, three@foo.com', 'cc';
};

subtest "no cc or bcc" => sub {
    my $target = Email::MIME::Kit::Bulk::Target->new(
        to => 'one@foo.com',
        language => 'en',
        template_params => {
            superlative => 'Wicked',
        },
    );

    my $email = $bulk->assemble_mime_kit( $target );

    is $email->header('From') => 'me@here.com', 'from';
    is $email->header('To') => 'one@foo.com', 'to';
    is $email->header('Cc') => undef, 'cc';
};

