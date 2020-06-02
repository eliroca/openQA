# Copyright (C) 2014-2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

use Test::Most;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Warnings ':report_warnings';
use Test::Output 'combined_like';
use Mojolicious;
use OpenQA::Setup;
use OpenQA::JobGroupDefaults;
use OpenQA::Task::Job::Limit;
use Mojo::File 'tempdir';


sub read_config {
    my ($app, $msg) = @_;
    $msg //= 'reading config from default';
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    combined_like sub { OpenQA::Setup::read_config($app) }, qr/fallback to default/, $msg;
    return $app->config;
}

subtest 'Test configuration default modes' => sub {
    local $ENV{OPENQA_CONFIG} = undef;

    my $app = Mojolicious->new();
    $app->mode("test");
    my $config = read_config($app, 'reading config from default with mode test');
    is(length($config->{_openid_secret}), 16, "config has openid_secret");
    my $test_config = {
        global => {
            appname                     => 'openQA',
            branding                    => 'openSUSE',
            hsts                        => 365,
            audit_enabled               => 1,
            max_rss_limit               => 0,
            profiling_enabled           => 0,
            monitoring_enabled          => 0,
            hide_asset_types            => 'repo',
            recognized_referers         => [],
            changelog_file              => '/usr/share/openqa/public/Changelog',
            job_investigate_ignore      => '"(JOBTOKEN|NAME)"',
            job_investigate_git_timeout => 20,
        },
        auth => {
            method => 'Fake',
        },
        'scm git' => {
            update_remote => '',
            update_branch => '',
            do_push       => 'no',
        },
        openid => {
            provider  => 'https://www.opensuse.org/openid/user/',
            httpsonly => 1,
        },
        hypnotoad => {
            listen => ['http://localhost:9526/'],
            proxy  => 1,
        },
        audit => {
            blacklist => '',
        },
        plugin_links => {
            operator => {},
            admin    => {}
        },
        amqp => {
            reconnect_timeout => 5,
            url               => 'amqp://guest:guest@localhost:5672/',
            exchange          => 'pubsub',
            topic_prefix      => 'suse',
        },
        obs_rsync => {
            home               => '',
            retry_interval     => 60,
            retry_max_count    => 1400,
            queue_limit        => 200,
            concurrency        => 2,
            project_status_url => '',
        },
        default_group_limits => {
            asset_size_limit                  => OpenQA::JobGroupDefaults::SIZE_LIMIT_GB,
            log_storage_duration              => OpenQA::JobGroupDefaults::KEEP_LOGS_IN_DAYS,
            important_log_storage_duration    => OpenQA::JobGroupDefaults::KEEP_IMPORTANT_LOGS_IN_DAYS,
            result_storage_duration           => OpenQA::JobGroupDefaults::KEEP_RESULTS_IN_DAYS,
            important_result_storage_duration => OpenQA::JobGroupDefaults::KEEP_IMPORTANT_RESULTS_IN_DAYS,
        },
        misc_limits => {
            untracked_assets_storage_duration         => 14,
            screenshot_cleanup_batch_size             => OpenQA::Task::Job::Limit::DEFAULT_SCREENSHOTS_PER_BATCH,
            screenshot_cleanup_batches_per_minion_job => OpenQA::Task::Job::Limit::DEFAULT_BATCHES_PER_MINION_JOB,
        },
    };

    # Test configuration generation with "test" mode
    $test_config->{_openid_secret} = $config->{_openid_secret};
    $test_config->{logging}->{level} = "debug";
    is_deeply $config, $test_config, '"test" configuration';

    # Test configuration generation with "development" mode
    $app = Mojolicious->new();
    $app->mode("development");
    $config = read_config($app, 'reading config from default with mode development');
    $test_config->{_openid_secret} = $config->{_openid_secret};
    is_deeply $config, $test_config, 'right "development" configuration';

    # Test configuration generation with an unknown mode (should fallback to default)
    $app = Mojolicious->new();
    $app->mode("foo_bar");
    $config                        = read_config($app, 'reading config from default with mode foo_bar');
    $test_config->{_openid_secret} = $config->{_openid_secret};
    $test_config->{auth}->{method} = "OpenID";
    delete $test_config->{logging};
    is_deeply $config, $test_config, 'right default configuration';
};

subtest 'Test configuration override from file' => sub {

    my $t_dir = tempdir;
    local $ENV{OPENQA_CONFIG} = $t_dir;
    my $app  = Mojolicious->new();
    my @data = (
        "[global]\n",
        "suse_mirror=http://blah/\n",
"recognized_referers = bugzilla.suse.com bugzilla.opensuse.org bugzilla.novell.com bugzilla.microfocus.com progress.opensuse.org github.com\n",
        "[audit]\n",
        "blacklist = job_grab job_done\n",
        "[assets/storage_duration]\n",
        "-CURRENT = 40\n"
    );
    $t_dir->child("openqa.ini")->spurt(@data);
    OpenQA::Setup::read_config($app);

    ok -e $t_dir->child("openqa.ini");
    ok($app->config->{global}->{suse_mirror} eq 'http://blah/',   'suse mirror');
    ok($app->config->{audit}->{blacklist} eq 'job_grab job_done', 'audit blacklist');
    is($app->config->{'assets/storage_duration'}->{'-CURRENT'}, 40, 'assets/storage_duration');

    is_deeply(
        $app->config->{global}->{recognized_referers},
        [
            qw(bugzilla.suse.com bugzilla.opensuse.org bugzilla.novell.com bugzilla.microfocus.com progress.opensuse.org github.com)
        ],
        'referers parsed correctly'
    );
};

subtest 'trim whitespace characters from both ends of openqa.ini value' => sub {

    my $t_dir = tempdir;
    local $ENV{OPENQA_CONFIG} = $t_dir;
    my $app  = Mojolicious->new();
    my $data = '
        [global]
        appname =  openQA  
        hide_asset_types = repo iso  
        recognized_referers =   bugzilla.suse.com   bugzilla.novell.com   bugzilla.microfocus.com   progress.opensuse.org github.com
    ';
    $t_dir->child('openqa.ini')->spurt($data);
    OpenQA::Setup::read_config($app);
    print $app->config->{global}->{appname};
    print $app->config->{global}->{hide_asset_types};
    ok($app->config->{global}->{appname} eq 'openQA',            'appname');
    ok($app->config->{global}->{hide_asset_types} eq 'repo iso', 'hide_asset_types');
    is_deeply(
        $app->config->{global}->{recognized_referers},
        [qw(bugzilla.suse.com bugzilla.novell.com bugzilla.microfocus.com progress.opensuse.org github.com)],
        'recognized_referers'
    );
};

done_testing();
