package App::Blumenkraft::Plugin::dump_plugins;

sub start {
    return 1; 
};

sub head { 
    my ($self, $vars, $head) = @_;

    $vars->{list} =
        sprintf "<pre>\n%s\n</pre>\n", join("\n", @{$vars->{plugin_list}});
}

1;
