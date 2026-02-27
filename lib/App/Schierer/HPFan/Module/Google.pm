package App::Schierer::HPFan::Module::Google;
# cspell: disable

use v5.42.0;
use utf8::all;
use Mooish::Base -role;
with 'WebFramework::Role::Logger';
extends 'Thunderhorse::Module';
use Future::AsyncAwait;

use Mojo::DOM58;
use HTML::Escape qw(escape_html);

use Path::Tiny;

const $googlescript =
qq{<script async src="https://www.googletagmanager.com/gtag/js?id=G-9KF1R3YFTZ"></script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());

      gtag('config', 'G-9KF1R3YFTZ');
    </script>};

1;
__END__   
