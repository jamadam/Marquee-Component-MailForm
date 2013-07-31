package Marquee::Component::MailFormExample;
use strict;
use warnings;
use utf8;
use Mojo::Base qw(Marquee::Component::MailForm);
    
    sub new {
        my $self = shift->SUPER::new(@_);
        my ($app) = @_;
        $self->tmp_dir('');
        $self->mailto(['noreply@example.com']);
        $self->logfile($app->home->rel_file('log/contact_form.dat'));
        $self->smtp_from('noreply'); ## you can fill @host if needed
        $self->smtp_server('localhost');
        $self->form_elements([qw{name mail pref addr company tel1 tel2 tel3 fax1 fax2 fax3 etc}]);
        $self->form_elements([qw{name1 name2 kana1 kana2 zip1 zip2 pref addr1 addr2 addr3 tel1 tel2 tel3 fax1 fax2 fax3 mail1 mail2 msg}]);
        $self->auto_respond_to('mail1');
        $self->upload({
            allowed_extention => ['doc','xls','txt','pdf'],
            max_filesize => 100000,
        });
    }

    sub validate_form {
        my ($self) = @_;
        my $c = Marquee->c;
        my $formdata = $c->tx->req->body_params;
        my $user_err = $self->user_err;
        
        if (! ($formdata->param('name1') && $formdata->param('name2') &&
               $formdata->param('kana1') && $formdata->param('kana2'))) {
            $user_err->stack('お名前は必須項目です');
        }
        if ($formdata->param('tel1') && $formdata->param('tel2') && $formdata->param('tel3')) {
            for my $key ('tel1', 'tel2', 'tel3') {
                my $num = $formdata->param($key);
                $num =~ tr/０-９/0-9/;
                $formdata->param($key, $num);
                if ($num =~ qr{[^\d]}) {
                    $user_err->stack('お電話番号は数値で入力してください');
                }
            }
        } else {
            $user_err->stack('お電話番号は必須項目です');
        }
        if ($formdata->param('fax1') && $formdata->param('fax2') && $formdata->param('fax3')) {
            for my $key ('fax1', 'fax2', 'fax3') {
                my $num = $formdata->param($key);
                $num =~ tr/０-９/0-9/;
                $formdata->param($key, $num);
                if ($num =~ qr{[^\d]}) {
                    $user_err->stack('お電話番号は数値で入力してください');
                }
            }
        }
        if (my $mail = $formdata->param('mail1')) {
            $mail =~ tr/Ａ-Ｚａ-ｚ０-９/A-Za-z0-9/;
            if ($mail !~ /^[^@]+@[^.]+\..+/){
                $user_err->stack('メールアドレスが正しくありません');
            } elsif ($mail ne $formdata->param('mail2')) {
                $user_err->stack('メールアドレスが確認用と一致しません');
            }
        } else {
            $user_err->stack('メールアドレスは必須項目です');
        }
        if (! $formdata->param('msg')) {
            $user_err->stack('お問合せ内容は必須項目です');
        }
        if ($formdata->param('msg') && length($formdata->param('msg')) > 10000) {
            $user_err->stack('お問い合わせ内容がサイズの上限を超えました');
        }
    }
    
    sub mail_attr {
        my ($self) = @_;
        
        my $tpl = __PACKAGE__->Marquee::asset('mail_forward.html.ep');
		my $body = Marquee->c->app->dynamic->render($tpl);
        
        return 'お問い合わせがありました', $body;
    }
    
    sub mail_attr_respond {
        my ($self) = @_;
        
        my $tpl = __PACKAGE__->Marquee::asset('mail_respond.html.ep');
		my $body = Marquee->c->app->dynamic->render($tpl);
        
        return 'お問合せを承りました', $body;
    }

1;

__END__

=head1 NAME

Marquee::Component::MailFormExample

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=cut
