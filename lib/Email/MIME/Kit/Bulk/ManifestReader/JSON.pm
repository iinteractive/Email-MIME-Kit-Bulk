package Email::MIME::Kit::Bulk::ManifestReader::JSON;
# ABSTRACT: Extension of E::M::K::ManifestReader::JSON for Email::MIME::Kit::Bulk

=head1 DESCRIPTION

Extends L<Email::MIME::Kit::ManifestReader::JSON>. The manifest of the 
kit will be 'C<manifest.I<language>.json>', where I<language> is provided
via 'C<targets.json>'. If no language is given, the manifest file defaults
to 'C<manifest.json>'.

=cut 

use Moose;

extends 'Email::MIME::Kit::ManifestReader::JSON';

sub read_manifest {
    my ($self) = @_;

    my $manifest = 'manifest.json';
    if ($self->kit->has_language) {
        $manifest = 'manifest.' . $self->kit->language . '.json';
    }

    my $json_ref = $self->kit->kit_reader->get_kit_entry($manifest);

    my $content = JSON->new->decode($$json_ref);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
