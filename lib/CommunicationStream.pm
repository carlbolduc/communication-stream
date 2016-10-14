package CommunicationStream;
use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use URI::Escape;
use WWW::Mechanize;
use HTML::TreeBuilder;
use HTML::FormatText;
use DateTime;
use DateTime::Format::Strptime;
use SOAP::Lite;

our $VERSION = '0.1';

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;


my $soap = SOAP::Lite
    -> uri('http://localhost/coveosearch.asmx')
    -> on_action( sub { join '/', 'http://www.coveo.com/SearchService', $_[1] } )
    -> proxy('http://localhost/coveosearch.asmx?WSDL');
my $method = SOAP::Data->name('PerformQuery')
    ->attr({xmlns => 'http://www.coveo.com/SearchService'});
    
sub SOAP::Transport::HTTP::Client::get_basic_credentials { 
    return '...\...' => '...';
}

my $firstResult = 0;

get '/:ref' => sub {
    my @messages = ();
    my ($modifiedDate, $quickViewLinks, $linkToDocuments, $outlookProtocolLinks, $containsAttachment) = getCachedDocumentUris(params->{ref}, 0, 5); #fix this to use the number of documents
    my $i = 0;
    foreach my $quickViewLink (@{$quickViewLinks}) {
        my $text = grab_page($quickViewLink);
        my $datetime = getDisplayDate(${$modifiedDate}[$i]);
        my ($date, $timestamp) = split(/\|/, $datetime);
        if (index($text, "class=\"email") != -1) {
            if (${$containsAttachment}[$i] eq "true") {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$outlookProtocolLinks}[$i] . "\"><img src=\"/images/emailInbound.gif\" /></a>", text => $text, attachment => "<img src=\"/images/emailHasAttach.gif\" />"});
          } else {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$outlookProtocolLinks}[$i] . "\"><img src=\"/images/emailInbound.gif\" /></a>", text => $text});
          }
        }
        elsif (index($text,"||") != -1) {
            my @linkAndText = split(/\|\|/, $text);
            push(@messages, {date => $date, timestamp => $timestamp, link => $linkAndText[0], text => $linkAndText[1]});
        }
        else {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$linkToDocuments}[$i] . "\"><img src=\"/images/comment_icon.gif\" /></a>", text => $text});
        }
        $i++;
    }
    template 'index' => {messages => \@messages};
    #extract a list of links
    #for all the links, fetch the body and add it to a var
};

ajax '/getNextResults:firstResultAndRef' => sub {
    my $content = '';
    my ($salesforceRef, $firstResult) = split(/\|/, params->{firstResultAndRef});
    my @messages = ();
    my ($modifiedDate, $quickViewLinks, $linkToDocuments, $outlookProtocolLinks) = getCachedDocumentUris($salesforceRef, $firstResult, 5);
    my $i = 0;
    foreach my $quickViewLink (@{$quickViewLinks}) {
        my $text = grab_page($quickViewLink);
        my $datetime = getDisplayDate(${$modifiedDate}[$i]);
        my ($date, $timestamp) = split(/\|/, $datetime);
        if (index($text, "class=\"email") != -1) {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$outlookProtocolLinks}[$i] . "\"><img src=\"/images/emailInbound.gif\" /></a>", text => $text});
        }
        elsif (index($text,"||") != -1) {
            my @linkAndText = split(/\|\|/, $text);
            push(@messages, {date => $date, timestamp => $timestamp, link => $linkAndText[0], text => $linkAndText[1]});
        }
        else {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$linkToDocuments}[$i] . "\"><img src=\"/images/comment_icon.gif\" /></a>", text => $text});
        }
        $i++;
    }
    $content = template 'messages' => {messages => \@messages};
    
    {
        content => $content
    }
    ;
};

ajax '/getAllResults:firstResultAndRef' => sub {
    my $content = '';
    my ($salesforceRef, $firstResult) = split(/\|/, params->{firstResultAndRef});
    my @messages = ();
    my ($modifiedDate, $quickViewLinks, $linkToDocuments, $outlookProtocolLinks) = getCachedDocumentUris($salesforceRef, $firstResult, 1000);
    my $i = 0;
    foreach my $quickViewLink (@{$quickViewLinks}) {
        my $text = grab_page($quickViewLink);
        my $datetime = getDisplayDate(${$modifiedDate}[$i]);
        my ($date, $timestamp) = split(/\|/, $datetime);
        if (index($text, "class=\"email") != -1) {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$outlookProtocolLinks}[$i] . "\"><img src=\"/images/emailInbound.gif\" /></a>", text => $text});
        }
        elsif (index($text,"||") != -1) {
            my @linkAndText = split(/\|\|/, $text);
            push(@messages, {date => $date, timestamp => $timestamp, link => $linkAndText[0], text => $linkAndText[1]});
        }
        else {
            push(@messages, {date => $date, timestamp => $timestamp, link => "<a href=\"" . ${$linkToDocuments}[$i] . "\"><img src=\"/images/comment_icon.gif\" /></a>", text => $text});
        }
        $i++;
    }
    $content = template 'messages' => {messages => \@messages};
    
    {
        content => $content
    }
    ;
};

sub getResults {
    my ($query, $firstResult, $numberOfResults) = ($_[0], $_[1], $_[2]);
    my @params = (SOAP::Data->name("p_Params"=>
                                       \SOAP::Data->value(SOAP::Data->name("BasicQuery" => $query) -> type("string"),
                                                          SOAP::Data->name("NumberOfResults" => $numberOfResults),
                                                          SOAP::Data->name("SortCriteria" => "ModifiedDateDescending"),
                                                          SOAP::Data->name("NeedCachedDocumentUris" => "true"),
                                                          SOAP::Data->name("FirstResult" => $firstResult),
                                                          SOAP::Data->name("TimeZoneOffset" => 4),
                                                          SOAP::Data->name("NeededFields" =>
                                                                               \SOAP::Data->name("string" => "\@sysoutlookuri")))));
    my $result = $soap->call($method => @params);
    return $result;
}

sub getCachedDocumentUris {
    my @URIs;
    my ($salesforceRef, $firstResult, $numberOfResults) = ($_[0], $_[1], $_[2]);
    my $SearchResults = getResults("$salesforceRef \@sysfiletype==(exchangemessage,SFCaseComment)", $firstResult, $numberOfResults);
    my @modifiedDate = $SearchResults->valueof('//PerformQueryResponse/PerformQueryResult/Results/QueryResult/ModifiedDate');
    my @tmpURIs = $SearchResults->valueof('//PerformQueryResponse/PerformQueryResult/Results/QueryResult/CachedDocumentUri');
    my @clickableURIs = $SearchResults->valueof('//PerformQueryResponse/PerformQueryResult/Results/QueryResult/TargetUri');
    my @outlookURIs = $SearchResults->valueof('//PerformQueryResponse/PerformQueryResult/Results/QueryResult/Fields/ResultField/Value');
    my @containsAttachment = $SearchResults->valueof('//PerformQueryResponse/PerformQueryResult/Results/QueryResult/ContainsAttachment');
    foreach my $URI (@tmpURIs) {
        my ($LeftURI, $RemainingURI) = split('&docid=', $URI);
        my ($MiddleURI, $RightURI) = split('&q=', $RemainingURI);
        $MiddleURI =~ s/:/%3A/g;
        $MiddleURI =~ s/@/%40/g;
        $MiddleURI =~ s/\//%2F/g;
        $MiddleURI =~ s/\$/%24/g;
        $MiddleURI =~ s/é/%C3%A9/g;
        $MiddleURI =~ s/\+/%2b/g;
        $MiddleURI =~ s/Messages%2bTrait%C3%A9s/Messages\+Trait%C3%A9s/g;
        #push (@URIs, uri_escape($URI));
        push (@URIs, $LeftURI . '&docid=' . $MiddleURI . '&q=' . $RightURI);
    }
    return (\@modifiedDate, \@URIs, \@clickableURIs, \@outlookURIs, \@containsAttachment);
}

sub grab_page {
    my @SupportAgents = ("Carl Bolduc", "Tom York", "Jeff Cavaliere");
    # using shift to accept parameter passed to method
    my $urlString = shift;
    my $username = "...\\...";
    my $password = "...";
    my $mech = WWW::Mechanize->new(autocheck => 0);
    $mech->agent('Mozilla/5.0 (Windows NT 6.1; WOW64; rv:2.0.1) Gecko/20100101 Firefox/4.0.1');
    $mech->credentials($username, $password);
    my $response = $mech->get($urlString);
    my $page_contents = $mech->content();
    my $Format = HTML::FormatText->new(leftmargin => 0);
    my $TreeBuilder = HTML::TreeBuilder->new;
    $TreeBuilder->parse($page_contents);
    my $Parsed = $Format->format($TreeBuilder);
    my (@EmailsEnglish, @EmailsFrench);
    my $FirstEmail;
    # is this an email exchange
    if (index($Parsed,"From:") != -1) { 
        @EmailsEnglish = split(/From:/,$Parsed);
        $FirstEmail = $EmailsEnglish[0];
        $FirstEmail =~ s/\n/<br>/g;
        $FirstEmail =~ s/-+\s?Original Message\s?-+//g;
        $FirstEmail =~ s/(<br>){3,}/<br>/g;
        return "<div class=\"email\">$FirstEmail</div>";
    } elsif (index($Parsed,"De:") != -1) {
        @EmailsFrench = split(/De:/,$Parsed);
        $FirstEmail = $EmailsFrench[0];
        $FirstEmail =~ s/\n/<br>/g;
        return "<div class=\"email\">$FirstEmail</div>";
    }
    # is this a mantis exchange
    elsif (index($Parsed,"================") != -1) {
        my $LastNote = substr($Parsed,rindex($Parsed,"----------------------------------------------------------------------",rindex($Parsed, "----------------------------------------------------------------------") -1)); 
        $LastNote = substr($LastNote,0,index($LastNote,"==========="));
        my $LastNoteAuthor = substr($LastNote,0,rindex($LastNote,"----------------------------------------------------------------------"));
        $LastNoteAuthor =~ s/-{11,}//g;
        # Extract the link to the mantis comment
        my $MantisLink = "";
        if ($LastNoteAuthor =~ m/http:\/\/mantis\/view.php\?id=\d*#c\d*/) {
            $MantisLink = $&;
        }
        # Detect if Dev or Support is speaking
        foreach (@SupportAgents) {
            if (index($LastNoteAuthor,$_) != -1) {
                $LastNoteAuthor = "Support:";
                last;
            } else {
                $LastNoteAuthor = "Dev:";
            }
        }
        my $LastNoteMessage = substr($LastNote,rindex($LastNote,"----------------------------------------------------------------------"));
        $LastNoteMessage =~ s/-{11,}//g;
        $LastNoteMessage =~ s/\n/<br>/g;
        $LastNoteMessage =~ s/(<br>){3,}/<br>/g;
        return "<a href=\"" . $MantisLink . "\" target=\"_blank\"><img src=\"/images/mantis.gif\" /></a>||<div class=\"mantis\">" . $LastNoteAuthor . "<br>" . $LastNoteMessage . "</div>";
    } else {
        $Parsed =~ s/\n/<br>/g;
        $Parsed =~ s/(<br>){3,}/<br>/g;
        #salesforce comment
        return "<div class=\"comment\">$Parsed</div>";
    }
}

sub getDisplayDate {
    my $modifiedDate = $_[0]; #"20090103 12:00";
    my $format = new DateTime::Format::Strptime(
                    pattern => '%Y-%m-%dT%H:%M:%S',
                    time_zone => 'GMT',
                    );
    my $date = $format->parse_datetime($modifiedDate);
    $date->set_time_zone("America/New_York");
    return $date->day_abbr().", ".$date->month_abbr()." ".$date->strftime("%d|%H:%M");
}


true;