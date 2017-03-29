package Email::MIME::Kit::Bulk::Kit;
# ABSTRACT: Email::MIME kit customized for Email::MIME::Kit::Bulk

=head1 DESCRIPTION

I<Email::MIME::Kit::Bulk::Kit> extends L<Email::MIME::Kit>. It defaults the C<manifest_reader>
attribute to L<Email::MIME::Kit::Bulk::ManifestReader::JSON>, and add a new 
C<language> attribute.

=cut

use strict;
use warnings;

use Email::MIME::Kit::Bulk::ManifestReader::JSON;

use Moose;

extends 'Email::MIME::Kit';

has '+_manifest_reader_seed' => (
    default => '=Email::MIME::Kit::Bulk::ManifestReader::JSON',
);

has language => (
    is        => 'ro',
    isa       => 'Str',
    predicate => 'has_language',
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;
