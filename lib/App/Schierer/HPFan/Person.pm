package App::Schierer::HPFan::Person;

use strict;
use warnings;
use Moo;
use DBI;
use JSON::XS;
use Path::Tiny;
use Encode qw(encode_utf8);

has dbh => (
    is => 'lazy',
);

has template_file => (
    is => 'ro',
    default => 'templates/person/details.html.ep'
);

sub _build_dbh {
    my $self = shift;
    my $dbh = DBI->connect(
        "dbi:SQLite:dbname=share/grampsdb/sqlite.db",
        "", "",
        {
            RaiseError => 1,
            sqlite_unicode => 1,
        }
    );
    return $dbh;
}

sub get_person_by_gramps_id {
    my ($self, $gramps_id) = @_;
    
    my $sth = $self->dbh->prepare(
        "SELECT handle, given_name, surname, gramps_id, gender, json_data 
         FROM person WHERE gramps_id = ?"
    );
    $sth->execute($gramps_id);
    
    return $sth->fetchrow_hashref;
}

sub get_person_by_name {
    my ($self, $surname, $given_name) = @_;
    
    my $sth = $self->dbh->prepare(
        "SELECT handle, given_name, surname, gramps_id, gender, json_data 
         FROM person WHERE surname = ? AND given_name = ?"
    );
    $sth->execute($surname, $given_name);
    
    return $sth->fetchrow_hashref;
}

sub render_person_page {
    my ($self, $surname, $given_name, $static_content) = @_;
    
    my $person = $self->get_person_by_name($surname, $given_name);
    return unless $person;
    
    # Simple template rendering - just basic substitution for now
    my $template = path($self->template_file)->slurp_utf8;
    
    my $display_name = join(' ', 
        $person->{given_name} || '', 
        $person->{surname} || ''
    );
    $display_name =~ s/^\s+|\s+$//g;
    
    my $gender_icon = $person->{gender} == 1 ? 'ion-male' : 
                     $person->{gender} == 0 ? 'ion-female' : 
                     'tdesign:user-unknown';
    
    my $gender_class = $person->{gender} == 1 ? 'color-male' : 
                      $person->{gender} == 0 ? 'color-female' : 
                      'icon1';
    
    # Basic HTML template
    my $html = qq{
<!DOCTYPE html>
<html>
<head>
    <title>$display_name</title>
    <meta charset="utf-8">
    <link rel="stylesheet" href="/css/gramps.css" />
</head>
<body>
    <div class="basic-info spectrum-Card spectrum-Card--horizontal" id="$person->{gramps_id}">
        <div class="spectrum-Card-preview">
            <iconify-icon icon="$gender_icon" class="$gender_class" width="none"></iconify-icon>
        </div>
        <div class="spectrum-Card-body">
            <div class="spectrum-Card-header">
                <div class="spectrum-Card-title">$display_name</div>
            </div>
            <div class="spectrum-Card-content">
                <ul class="bio">
                    <li><strong>ID</strong>: $person->{gramps_id}</li>
                    <li><strong>Given Name</strong>: $person->{given_name}</li>
                    <li><strong>Surname</strong>: $person->{surname}</li>
                </ul>
            </div>
        </div>
    </div>
};
    
    if ($static_content) {
        $html .= qq{
    <hr />
    <h2>Analysis</h2>
    $static_content
};
    }
    
    $html .= qq{
</body>
</html>
};
    
    return $html;
}

sub get_all_people_names {
    my ($self) = @_;
    
    my $sth = $self->dbh->prepare("SELECT surname, given_name FROM person ORDER BY surname, given_name");
    $sth->execute();
    
    my @people;
    while (my $row = $sth->fetchrow_hashref) {
        push @people, {
            surname => $row->{surname},
            given_name => $row->{given_name}
        };
    }
    
    return \@people;
}

1;
