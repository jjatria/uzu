use v6;
use lib 'lib';

use Test;
use Test::Output;
use Uzu::Config;
use Uzu::HTTP;
use Uzu::Render;
use Uzu::Utilities;
use File::Temp;

plan 3;

# Source project files
my $test_root   = $*CWD.IO.child('t');

subtest {
    plan 13;

    my $source_root = $test_root.IO.child('example_project_tt');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Generate HTML from templates
    my $stdout = stdout-from { Uzu::Render::build $config };
    say $stdout if %*ENV<UZUSTDOUT>;

    # Did we generate the build directory?
    my $tmp_build_path = $tmp_root.IO.child('build').path;
    is $tmp_build_path.IO.e, True, 'build directory created';

    # Did we copy the assets folder contents?
    is $tmp_build_path.IO.child('img').child('logo.png').IO.e, True, 'assets folder contents copied';

    # Did we copy the pulic folder contents?
    is $tmp_build_path.IO.child('robots.txt').IO.e, True, 'public folder contents copied';

    # Generated HTML looks good?
    my $t4_expected_html  = slurp $test_root.IO.child('expected_tt').child('index.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('index.html');
    is $t4_generated_html, $t4_expected_html, '[Template6] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t5_expected_html  = slurp $test_root.IO.child('expected_tt').child('blog').child('fiji.html');
    my $t5_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');
    is $t5_generated_html, $t5_expected_html, '[Template6] rendered nested HTML matches test';

    # Generated *_pages links exposed
    my $t6_expected_html  = slurp $test_root.IO.child('expected_tt').child('related.html');
    my $t6_generated_html = slurp $tmp_build_path.IO.child('related.html');
    is $t6_generated_html, $t6_expected_html, '[Template6] expose and utilize *_pages dict variables';

    # Use i18n language in uri for non-default languages
    my $t7_expected_html  = slurp $test_root.IO.child('expected_tt').child('related-ja.html');
    my $t7_generated_html = slurp $tmp_build_path.IO.child('related-ja.html');
    is $t7_generated_html, $t7_expected_html, '[Template6] i18n language in uri for non-default languages';

    # Use theme partial
    my $t8_expected_html  = slurp $test_root.IO.child('expected_tt').child('themepartial.html');
    my $t8_generated_html = slurp $tmp_build_path.IO.child('themepartial.html');
    is $t8_generated_html, $t8_expected_html, '[Template6] use theme partial';

    # Rebuild page when related page modified
    my $t9_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t9_related_page            = $tmp_root.IO.child('pages').child('about.tt');
    spurt $t9_related_page, slurp($t9_related_page);
    my $stdout9 = stdout-from { Uzu::Render::build $config };
    say $stdout9 if %*ENV<UZUSTDOUT>;
    my $t9_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t9_generated_post_modified > $t9_generated_pre_modified, '[Template6] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t10_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t10_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.tt');
    spurt $t10_unrelated_partial, slurp($t10_unrelated_partial);
    my $stdout10 = stdout-from { Uzu::Render::build $config };
    say $stdout10 if %*ENV<UZUSTDOUT>;
    my $t10_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t10_generated_post_modified == $t10_generated_pre_modified, '[Template6] modifying an unrelated partial does not trigger page rebuild';

    # Disable theme layout from page yaml
    my $t11_expected_html  = slurp $test_root.IO.child('expected_tt').child('nolayout.html');
    my $t11_generated_html = slurp $tmp_build_path.IO.child('nolayout.html');
    is $t11_generated_html, $t11_expected_html, '[Template6] disable theme layout from page yaml';

    # Embedded partials can access page vars
    my $t12_expected_html  = slurp $test_root.IO.child('expected_tt').child('embedded.html');
    my $t12_generated_html = slurp $tmp_build_path.IO.child('embedded.html');
    is $t12_generated_html, $t12_expected_html, '[Template6] embedded partials can access page vars';

    # Deeply embedded partials can access page vars
    my $t13_expected_html  = slurp $test_root.IO.child('expected_tt').child('deepembed.html');
    my $t13_generated_html = slurp $tmp_build_path.IO.child('deepembed.html');
    is $t13_generated_html, $t13_expected_html, '[Template6] deeply embedded partials can access page vars';
}, 'Rendering [Defaults]';

subtest {
    plan 10;

    my $source_root = $test_root.IO.child('example_project_mustache');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Generate HTML from templates
    my $stdout = stdout-from { Uzu::Render::build $config };
    say $stdout if %*ENV<UZUSTDOUT>;

    my $tmp_build_path = $tmp_root.IO.child('build').path;

    # Generated HTML looks good?
    my $t1_expected_html  = slurp $test_root.IO.child('expected_mustache').child('index.html');
    my $t1_generated_html = slurp $tmp_build_path.IO.child('index.html');
    is $t1_generated_html, $t1_expected_html, '[Mustache] rendered HTML matches test';

    # Generated nested HTML looks good?
    my $t2_expected_html  = slurp $test_root.IO.child('expected_mustache').child('blog').child('fiji.html');
    my $t2_generated_html = slurp $tmp_build_path.IO.child('blog').child('fiji.html');
    is $t2_generated_html, $t2_expected_html, '[Mustache] rendered nested HTML matches test';

    # Generated *_pages links exposed
    my $t3_expected_html  = slurp $test_root.IO.child('expected_mustache').child('related.html');
    my $t3_generated_html = slurp $tmp_build_path.IO.child('related.html');
    is $t3_generated_html, $t3_expected_html, '[Mustache] expose and utilize *_pages dict variables';

    # Use i18n language in uri for non-default languages
    my $t4_expected_html  = slurp $test_root.IO.child('expected_mustache').child('related-ja.html');
    my $t4_generated_html = slurp $tmp_build_path.IO.child('related-ja.html');
    is $t4_generated_html, $t4_expected_html, '[Mustache] i18n language in uri for non-default languages';

    # Use theme partial
    my $t5_expected_html  = slurp $test_root.IO.child('expected_mustache').child('themepartial.html');
    my $t5_generated_html = slurp $tmp_build_path.IO.child('themepartial.html');
    is $t5_generated_html, $t5_expected_html, '[Mustache] use theme partial';

    # Rebuild page when related page modified
    my $t6_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t6_related_page            = $tmp_root.IO.child('pages').child('about.mustache');
    spurt $t6_related_page, slurp($t6_related_page);
    my $stdout6 = stdout-from { Uzu::Render::build $config };
    say $stdout6 if %*ENV<UZUSTDOUT>;
    my $t6_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t6_generated_post_modified > $t6_generated_pre_modified, '[Mustache] modifying a related page triggers page rebuild';

    # Modifying an unrelated partial does not trigger page rebuild
    my $t7_generated_pre_modified  = $tmp_build_path.IO.child('related.html').modified;
    my $t7_unrelated_partial       = $tmp_root.IO.child('partials').child('usetheme.mustache');
    spurt $t7_unrelated_partial, slurp($t7_unrelated_partial);
    my $stdout7 = stdout-from { Uzu::Render::build $config };
    say $stdout7 if %*ENV<UZUSTDOUT>;
    my $t7_generated_post_modified = $tmp_build_path.IO.child('related.html').modified;
    ok $t7_generated_post_modified == $t7_generated_pre_modified, '[Mustache] modifying an unrelated partial does not trigger page rebuild';

    # Disable theme layout from page yaml
    my $t8_expected_html  = slurp $test_root.IO.child('expected_mustache').child('nolayout.html');
    my $t8_generated_html = slurp $tmp_build_path.IO.child('nolayout.html');
    is $t8_generated_html, $t8_expected_html, '[Mustache] disable theme layout from page yaml';

    # Embedded partials can access page vars
    my $t9_expected_html  = slurp $test_root.IO.child('expected_mustache').child('embedded.html');
    my $t9_generated_html = slurp $tmp_build_path.IO.child('embedded.html');
    is $t9_generated_html, $t9_expected_html, '[Mustache] embedded partials can access page vars';

    # Deeply embedded partials can access page vars
    my $t10_expected_html  = slurp $test_root.IO.child('expected_mustache').child('deepembed.html');
    my $t10_generated_html = slurp $tmp_build_path.IO.child('deepembed.html');
    is $t10_generated_html, $t10_expected_html, '[Mustache] deeply embedded partials can access page vars';
}, 'Rendering [Mustache]';

subtest {
    plan 3;

    my $source_root = $test_root.IO.child('example_project_tt');

    # Setup tmp project root
    my $tmp_root    = tempdir;

    # Copy all example project files to tmp project root
    copy-dir $source_root, $tmp_root.IO;

    # Add tmp path to project config
    my $config_path = $tmp_root.IO.child('config.yml');
    my $config_file = slurp $config_path;
    spurt $config_path, $config_file ~ "project_root: $tmp_root\n";

    # Set config file path
    my $config = Uzu::Config::from-file config_file => $config_path, no_livereload => True;

    # Expect a warning when i18n yaml is invalid
    my $yaml = q:to/END/;
    ---
    company: Sam Morrison
    site_name: Uzu Test Project
    # Need to quote strings that start with numbers
    copyright: 2016 Sam Morrison
    ...
    END

    # Save to tmp_build_path i18n yaml file
    spurt $tmp_root.IO.child('i18n').child('en.yml'), $yaml;

    # Do not die when theme layout template is missing
    unlink $tmp_root.IO.child('themes').child('default').child('layout.tt');

    my $build_out = output-from { Uzu::Render::build $config };
    say $build_out if %*ENV<UZUSTDOUT>;

    # Test warnings
    like $build_out, / "No content found for page" /, 'empty page template warning to stdout';
    like $build_out, / "Invalid i18n yaml file" /, 'invalid i18n yaml warning to stdout';
    like $build_out, / "Theme [default] does not contain a layout template" /, 'theme layout template is missing warning to stdout';

}, 'Warnings';

# vim: ft=perl6
