package App::EbookUtils;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Perinci::Object;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

my %argspec0_files__epub = (
    files => {
        schema => ['array*', of=>'filename*', min_len=>1,
                   #uniq=>1, # not yet implemented by Data::Sah
               ],
        req => 1,
        pos => 0,
        slurpy => 1,
        'x.element_completion' => [filename => {filter => sub { /\.epub$/i }}],
    },
);

our %argspecopt_overwrite = (
    overwrite => {
        schema => 'bool*',
        cmdline_aliases => {O=>{}},
    },
);

$SPEC{convert_epub_to_pdf} = {
    v => 1.1,
    summary => 'Convert epub file to PDF',
    description => <<'_',

This utility is a simple wrapper to `ebook-convert`. It allows setting output
filenames (`foo.epub.pdf`) so you don't have to specify them manually. It also
allows processing multiple files in a single invocation

_
    args => {
        %argspec0_files__epub,
        %argspecopt_overwrite,
    },
    deps => {
        prog => 'ebook-convert',
    },
};
sub convert_epub_to_pdf {
    my %args = @_;

    require IPC::System::Options;

    my $envres = envresmulti();

    my $i = 0;
    for my $input_file (@{ $args{files} }) {
        log_info "[%d/%d] Processing file %s ...", ++$i, scalar(@{ $args{files} }), $input_file;
        $input_file =~ /(.+)\.(\w+)\z/ or do {
            $envres->add_result(412, "Please supply input file with extension in its name (e.g. foo.epub instead of foo)", {item_id=>$input_file});
            next;
        };
        my ($name, $ext) = ($1, $2);
        $ext =~ /\Aepub\z/i or do {
            $envres->add_result(412, "Input file '$input_file' does not have .epub extension", {item_id=>$input_file});
            next;
        };

        my $output_file = "$input_file.pdf";

        if (-e $output_file) {
            if ($args{overwrite}) {
                log_info "Unlinking existing PDF file %s ...", $output_file;
                unlink $output_file;
            } else {
                $envres->add_result(412, "Output file '$output_file' already exists, not overwriting (use --overwrite (-O) to overwrite)", {item_id=>$input_file});
                next;
            }
        }

        IPC::System::Options::system(
            {log=>1},
            "ebook-convert", $input_file, $output_file);
        my $exit_code = $? < 0 ? $? : $? >> 8;
        if ($exit_code) {
            $envres->add_result(500, "ebook-convert didn't return successfully, exit code=$exit_code", {item_id=>$input_file});
        } else {
            $envres->add_result(200, "OK", {item_id=>$input_file});
        }
    } # for $input_file

    $envres->as_struct;
}

1;
# ABSTRACT: Command-line utilities related to ebooks

=head1 SYNOPSIS


=head1 DESCRIPTION

This distribution provides tha following command-line utilities related to
ebooks:

#INSERT_EXECS_LIST


=head1 SEE ALSO

L<App::PDFUtils>

=cut
