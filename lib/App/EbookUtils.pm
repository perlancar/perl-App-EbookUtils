package App::EbookUtils;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use File::chdir;
use IPC::System::Options -log=>1, 'system';
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

my %argspec0_files__cbz = (
    files => {
        schema => ['array*', of=>'filename*', min_len=>1,
                   #uniq=>1, # not yet implemented by Data::Sah
               ],
        req => 1,
        pos => 0,
        slurpy => 1,
        'x.element_completion' => [filename => {filter => sub { /\.cbz$/i }}],
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
    description => <<'MARKDOWN',

This utility is a simple wrapper to `ebook-convert`. It allows setting output
filenames (`foo.epub.pdf`) so you don't have to specify them manually. It also
allows processing multiple files in a single invocation

MARKDOWN
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

        system("ebook-convert", $input_file, $output_file);
        my $exit_code = $? < 0 ? $? : $? >> 8;
        if ($exit_code) {
            $envres->add_result(500, "ebook-convert didn't return successfully, exit code=$exit_code", {item_id=>$input_file});
        } else {
            $envres->add_result(200, "OK", {item_id=>$input_file});
        }
    } # for $input_file

    $envres->as_struct;
}

sub _convert_cbz_to_pdf_single {
    my ($input_file, $output_file) = @_;

    log_debug("Creating temporary directory ...");
    require File::Temp;
    my $tempdir = File::Temp::tempdir(CLEANUP => log_is_debug() ? 0:1);
    log_debug("Temporary directory is $tempdir");

    require Cwd;
    my $abs_input_file = Cwd::abs_path($input_file)
        or return [500, "Can't get absolute path of input file '$input_file'"];
    my $abs_output_file = Cwd::abs_path($output_file)
        or return [500, "Can't get absolute path of output file '$output_file'"];

    log_debug("Extracting $abs_input_file ...");
    local $CWD = $tempdir;
    system("unzip", $abs_input_file);
    my $exit_code = $? < 0 ? $? : $? >> 8;
    return [500, "Can't unzip $abs_input_file ($exit_code): $!"]
        if $exit_code;

    log_debug("Converting images to PDFs ...");
    my @input_img_files = glob "*";
    my @input_pdf_files;
    my $num_files = @input_img_files;
    my $i = 0;
    for my $file (@input_img_files) {
        $i++;
        log_debug "[#%d/%d] Processing %s ...", $i, $num_files, $file;
        unless (-f $file) {
            log_warn "Found a non-regular file inside $input_file: $file, skipped";
            next;
        }
        system("convert", $file, "$file.pdf");
        my $exit_code = $? < 0 ? $? : $? >> 8;
        if ($exit_code) {
            log_error "Can't convert $file to $file.pdf ($exit_code): $!, skipped";
            next;
        }
        push @input_pdf_files, "$file.pdf";
    }

    log_debug "Combining all PDFs into a single one ...";
    system "pdftk", @input_pdf_files, "cat", "output", $abs_output_file;
    $exit_code = $? < 0 ? $? : $? >> 8;
    return [500, "Can't combine PDFs into a single one ($exit_code): $!"]
        if $exit_code;

    [200];
}

$SPEC{convert_cbz_to_pdf} = {
    v => 1.1,
    summary => 'Convert cbz file to PDF',
    description => <<'MARKDOWN',

MARKDOWN
    args => {
        %argspec0_files__cbz,
        %argspecopt_overwrite,
    },
    deps => {
        all => [
            {prog => 'unzip'},
            {prog => 'pdftk'},
            {prog => 'convert'},
        ],
    },
};
sub convert_cbz_to_pdf {
    my %args = @_;

    my $envres = envresmulti();

    my $i = 0;
    for my $input_file (@{ $args{files} }) {
        log_info "[%d/%d] Processing file %s ...", ++$i, scalar(@{ $args{files} }), $input_file;
        $input_file =~ /(.+)\.(\w+)\z/ or do {
            $envres->add_result(412, "Please supply input file with extension in its name (e.g. foo.cbz instead of foo)", {item_id=>$input_file});
            next;
        };
        my ($name, $ext) = ($1, $2);
        $ext =~ /\Acbz\z/i or do {
            $envres->add_result(412, "Input file '$input_file' does not have .cbz extension", {item_id=>$input_file});
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

        my $convert_res = _convert_cbz_to_pdf_single($input_file, $output_file);
        if ($convert_res->[0] != 200) {
            $envres->add_result($convert_res->[0], "Can't convert return successfully, $convert_res->[0] - $convert_res->[1]", {item_id=>$input_file});
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
