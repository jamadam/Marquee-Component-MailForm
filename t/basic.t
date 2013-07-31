use strict;
use warnings;
use utf8;
use FindBin;
use File::Basename 'dirname';
use File::Spec;
use lib join '/', File::Spec->splitdir(File::Spec->rel2abs(dirname(__FILE__))), '../lib';
use lib join '/', File::Spec->splitdir(File::Spec->rel2abs(dirname(__FILE__))), 'lib';
use Test::More;
use Test::Mojo::DOM;
use Marquee;
use Marquee::Component::MailFormExample;
use Mojo::Date;
    
    use Test::More tests => 23;

    my $app;
    my $t;
    $app = Marquee->new;
    $app->document_root("$FindBin::Bin/public_html");
    $app->log_file("$FindBin::Bin/Marquee.log");
    $app->default_file('index.html');
    
    $app->stash->{contact_form} = Marquee::Component::MailFormExample->new($app);
    
    $app->plugin(Router => sub {
        my $r = shift;
        $r->route(qr'^/index.html$')->via('post')->to(sub {
            $app->stash->{contact_form}->post;
        });
    });
    
    $t = Test::Mojo::DOM->new($app);
    
    ## First page
    
    $t->get_ok('/')
        ->status_is(200)
        ->text_is('title', 'MailForm Test')
        ->element_exists_not('#errorMessage')
        ->dom_inspector(sub {
            my $t = shift;
            $t->at('#name1')->attr_is('value', '');
        });
    
    ## Incompleted post
    
    $t->post_ok('/index.html', form => {name1 => 'name1'})
        ->status_is(200)
        ->text_is('title', 'MailForm Test')
        ->element_exists('#errorMessage')
        ->dom_inspector(sub {
            my $t = shift;
            $t->at('#error li')->get(0)->text_is('お名前は必須項目です');
            $t->at('#error li')->get(1)->text_is('お電話番号は必須項目です');
            $t->at('#error li')->get(3)->text_is('お問合せ内容は必須項目です');
            $t->at('#name1')->attr_is('value', 'name1');
            $t->at('#name2')->attr_is('value', '');
        });
    
    ## Confirm page
    
    $t->post_ok('/index.html', form => {
        nextpage=> 'confirm.html',
        name1   => 'name1',
        name2   => 'name2',
        kana1   => 'kana1',
        kana2   => 'kana2',
        pref    => '山形県',
        mail1   => 'example@example.com',
        mail2   => 'example@example.com',
        tel1    => '1',
        tel2    => '2',
        tel3    => '3',
        msg     => 'msg',
    })
        ->status_is(200)
        ->text_is('title', 'MailForm Test Confirm')
        ->element_exists_not('#errorMessage')
        ->dom_inspector(sub {
            my $t = shift;
            $t->at('input[name=name1]')->attr_is('value', 'name1');
            $t->at('input[name=name2]')->attr_is('value', 'name2');
            $t->at('input[name=kana1]')->attr_is('value', 'kana1');
            $t->at('input[name=kana2]')->attr_is('value', 'kana2');
            $t->at('input[name=pref]')->attr_is('value', '山形県');
        });
