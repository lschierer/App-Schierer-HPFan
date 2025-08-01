use Module::Build;

my $build = Module::Build->new(
    module_name        => 'App::Schierer::HPFan',
    license            => 'CC BY-NC 4.0', # Or another appropriate license
    dist_author        => 'Luke Schierer <luke@schierer.org>',
    dist_version_from  => 'lib/App/Schierer/HPFan.pm',
    requires           => {
        'perl' => '5.42', # Minimum Perl version
    },
    build_requires     => {
        'Test::More' => '0.98', # Example build dependency for testing
    },
    add_to_cleanup     => [ 'App-Schierer-HPFan-*' ],
    create_license     => 1,
    create_readme      => 1,
);

$build->create_build_script();
