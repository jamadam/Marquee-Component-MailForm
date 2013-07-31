package Marquee::Component::MailForm;
use strict;
use warnings;
use utf8;
use Mojo::Base -base;
use Encode;
use Net::SMTP;
use MIME::Lite;
use Fcntl qw(:flock);
use Carp;
our $VERSION = '0.01';

    __PACKAGE__->attr('mailto');
    __PACKAGE__->attr('tmp_dir');
    __PACKAGE__->attr('logfile');
    __PACKAGE__->attr('smtp_from');
    __PACKAGE__->attr('smtp_server');
    __PACKAGE__->attr('form_elements');
    __PACKAGE__->attr('auto_respond_to');
    __PACKAGE__->attr('upload');
    
    sub post {
        my ($self) = @_;
        my $c = Marquee->c;
        my $tx = $c->tx;
        my $app = Marquee->c->app;
        
        use Mojolicious::Sessions;
        if (! $c->session->{__PACKAGE__. '::session_id'}) {
            $c->session->{__PACKAGE__. '::session_id'} = session_id();
        }
        
        $self->validate_form;
        
        my $template;
        if ($self->user_err->count) {
            $c->tx->req->method('get');
            $app->dispatch;
        } else {
            if ($tx->req->body_params->param('send')) {
                $self->sendmail;
                $app->serve_redirect($tx->req->body_params->param('nextpage'));
            } else {
                my $template = $tx->req->body_params->param('nextpage');
                $app->dynamic->serve($app->dynamic->search($template));
            }
        }
    }
    
    sub save_temporary_file {
        my ($self) = @_;
        my $c = Marquee->c;
        my @files = $c->req->upload('file');
        foreach my $file (@files) {
            my $name = $c->session->{__PACKAGE__. '::session_id'}. '_file_'. $file->filename;
            my $tmp_name = File::Spec->catfile($self->upload->{dir}, $name);
            $file->move_to($tmp_name);
        }
    }
    
    sub validate_form {
        croak 'It must be implemented by sub classes';
    }
    
    sub sendmail_forward {
        my ($self) = @_;
        my $c = Marquee->c;
        my $body = '';
        for my $key (@{$self->form_elements}) {
            $body .= sprintf("[%s]\n%s\n", $key, $c->req->body_params->param($key));
        }
        return 'Thank you for sending', $body;
    }
    
    sub sendmail_auto_respond {
        my ($self) = @_;
        my $c = Marquee->c;
        my $body = '';
        for my $key (@{$self->form_elements}) {
            $body .= sprintf("[%s]\n%s\n", $key, $c->req->body_params->param($key));
        }
        return 'Thank you for sending', $body;
    }
    
    sub sendmail {
        my ($self) = @_;
        my $c = Marquee->c;
        my $tx = $c->tx;
        my $mailto = $self->mailto;
        my $auto_respond_to = $tx->req->body_params->param($self->auto_respond_to);
        
        my @attach = ();
        if ($self->upload) {
            opendir(my $dir, $self->upload->{dir}) or die "Unable to open upload directory";
            my $filename_base = $c->session->{__PACKAGE__. '::session_id'};
            my @files = grep {
                $_ =~ /^$filename_base\_/
                && -f File::Spec->catfile($self->upload->{dir}, $_), 
            } readdir($dir);
            close($dir);
            foreach my $file (@files) {
                push(@attach, $self->upload->{dir}. "/". $file);
            }
        }
        
        my @mail_attr = $self->mail_attr;
        $self->sendmail_backend($mailto, @mail_attr, \@attach);
        $self->sendmail_backend($auto_respond_to, $self->mail_attr_respond);
        
        $self->write_log($mail_attr[1]);
        
        foreach my $file (@attach) {
            unlink $file;
        }
    }
    
    sub mail_attr {
        croak 'It must be implemented by sub classes';
    }
    
    sub mail_attr_respond {
        croak 'It must be implemented by sub classes';
    }
    
    sub html_to_plaintext {
        my $html = shift;
        if ($html =~ qr{<body.*?>(.+?)</body>}s) {
            $html = $1;
        }
        $html =~ s{<.+?>}{}g;
        $html =~ s{\t}{  }g;
        return $html;
    }
    
    sub sendmail_backend {
        my ($self, $to, $subject, $body, $attach) = @_;
        my $c = Marquee->c;
        
        $subject = encode('MIME-Header', $subject);
        
        my $plain = html_to_plaintext($body);
        
        utf8::encode($body);
        utf8::encode($plain);
        
        my $mime_sub = MIME::Lite->new(
            Type     => 'multipart/alternative',
        );
        $mime_sub->attach(
            Data     => $plain,
            Type     => 'text/plain; charset=utf-8',
            Encoding => 'Base64',
        );
        $mime_sub->attach(
            Data     => $body,
            Type     => 'text/html; charset=utf-8',
            Encoding => 'Quoted-printable',
        );
        
        $to = (ref $to) ? $to : [$to];
        
        for my $addr (@$to) {
            my $smtp = Net::SMTP->new($self->smtp_server);
            my $smtp_from = $self->smtp_from;
            if ($smtp_from !~ /\@/) {
                $smtp_from .= '@'. $c->tx->req->url->to_abs->host;
            }
            $smtp->mail($smtp_from);
            $smtp->to($addr);
            
            my $mime = MIME::Lite->new(
                From    => encode('MIME-Header', $smtp_from),
                To      => encode('MIME-Header', $addr),
                Subject => $subject,
                Type     => 'multipart/mixed',
            );
            $mime->attach($mime_sub);
            foreach my $name (@$attach) {
                my $send_name = $name;
                $send_name =~ s{^.+?_.+?_}{};
                $mime->attach(
                    Filename => $send_name,
                    Path     => $name,
                    Type     => 'application/octet-stream',
                    Encoding => 'Base64'
                );
            }
            $smtp->data();
            $smtp->datasend($mime->as_string);
            $smtp->datasend();
            $smtp->quit();
        }
    }
    
    sub put_all_elems_in_hidden {
        my ($self) = @_;
        my $c = Marquee->c;
        my $out = '';
        for my $key (@{$self->form_elements}) {
            my $val = $c->tx->req->body_params->param($key) || '';
            $out .= sprintf(qq{<input type="hidden" name="%s" value="%s" />}, $key, $val);
        }
        return $out;
    }
    
    sub write_log {
        my ($self, $body) = @_;
        if (my $file = $self->logfile) {
            my $time = localtime(time());
            open(my $fh, ">>:utf8", $file) || warn "$file cannot open\n";
            if ($fh and flock($fh, LOCK_EX)) {
                print $fh "=======================================================";
                print $fh "\nDate: $time";
                print $fh "\n";
                print $fh "\n$body";
                print $fh "\n";
            }
            close $fh;
            chmod(oct(777), $file);
        }
    }
    
    ### ---
    ### sha generator wrapper
    ### ---
    sub sha512_hex {
        my $seed = shift;
        my $hash;
        $hash ||= eval {
            require Digest::SHA;
            Digest::SHA::sha512_hex($seed);
        };
        $hash ||= eval {
            require Digest::SHA1;
            Digest::SHA1::sha512_hex($seed);
        };
        if ($hash) {
            return $hash;
        }
        die q{Library for SHA not available};
    }
    
    ### ---
    ### generate session id
    ### ---
    sub session_id {
        return sha512_hex($^T. $$. rand(1000000));
    }
    
    sub mail_id {
        my ($self, $addr, $body) = @_;
        return sha512_hex($^T. $body);
    }
    
    ### ---
    ### user_error
    ### ---
    sub user_err {
        my ($self) = @_;
        my $stash = Marquee->c->stash;
        if (! $stash->{user_err}) {
            $stash->set('user_err', Marquee::Component::MailForm::_UserError->new);
        }
        return $stash->{user_err};
    }

package Marquee::Component::MailForm::_UserError;
use strict;
use warnings;

    sub new {
        return bless [], shift;
    }
    
    sub stack {
        my ($self, $err) = @_;
        push(@$self, $err);
        return $self;
    }
    
    sub count {
        my ($self) = @_;
        return scalar @$self;
    }
    
    sub array {
        my ($self) = @_;
        return @$self;
    }

1;

__END__

=head1 NAME

Marquee::Component::MailForm

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 AUTHOR

Sugama Keita, E<lt>sugama@jamadam.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Sugama Keita.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
