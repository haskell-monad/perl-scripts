#!/usr/bin/perl

use 5.010;

use File::Basename;
use File::Copy;
use File::Path;
use POSIX;
use Term::ANSIColor qw(:constants);
use Getopt::Long;

# ./file-update.pl [-help/-?]
# ./file-update.pl  -user=centos -host=test -e check   检查目标服务器是否存在备份文件($back_suffix)
# ./file-update.pl  -user=centos -host=test -e test    测试是否可以连接到远程服务器执行命令
# ./file-update.pl  -user=centos -host=test -e parse   只尝试解析__DATA__中的数据，不执行其他操作
# ./file-update.pl  -user=centos -host=test -e all     依次执行/上传/备份/更新操作
# ./file-update.pl  -user=centos -host=test -e restore 还原已经更新的文件
# ./file-update.pl  -user=centos -host=test -e clear   刪除目标服务器的备份文件
# ./file-update.pl -e ssh-key                          使用perl-SSH::Batch包配置与远程服务器的连接

# 以下三个地址需要以"/"结尾
# 本地项目根目录(***使用者必须修改该目录***)
my $project_root_dir = "/Users/limengyu/IdeaProjects/iron_chat_service/";
# 远程临时目录(会先通过ssh上传到该目录,然后在执行更新)(***使用者可选修改该目录***)
my $remote_tmp_dir = "/tmp/dir/";
# 远程项目根目录(会使用`远程临时目录`中的内容进行替换)(***使用者必须修改该目录***)
my $remote_root_dir = "/home/centos/iron_chat_service/";

# 远程主机名(默认值)
my $host = "amzon-s1";
# 远程登录用户名(默认值)
my $user_name = "centos";
# 远程备份文件后缀(默认值)
my $back_suffix = "back-up";

my %upload_file_hash = ();
my @fileArray = ();
# 输出帮助
my $help = 0;
my @services = ();
# 暂时未使用
my $ssh = 1;
my $perl_ssh = 1;

GetOptions (
	"user=s" => \$user_name,
	"host|ip=s" => \$host,
	"ssh!"  => \$ssh,
	"perl!" => \$perl_ssh,
	"back=s"  => \$back_suffix,
	"make=s@" => \@services,
	"help|?"    => \$help,
	"exec|e=s"  =>  \&dispatcher
) or die ("不能识别的命令行参数!");

@services = split(/,/,join(/,/,@services));

print_help() if $help;

sub print_help {
	say BOLD RED "\nplease use:";
	say BOLD BLUE "\t ./file-update.pl -user[远程用户名] -host[远程主机名] -noperl[关闭Perl] -nossh[关闭SSH]  -back[备份文件名后缀] -make[服务1,服务2...] -e [test|ssh-key|check|parser|upload|backup|update|restore|clear|all]\n";
}

sub dispatcher {
	my ($opt_name,$opt_value) = @_;
        say BOLD YELLOW "当前配置:";
	say BOLD YELLOW "\t远程用户名: [$user_name]";
	say BOLD YELLOW "\t远程主机名: [$host]";
	say BOLD YELLOW "\t是否开启SSH: [$ssh]";
	say BOLD YELLOW "\t是否使用Perl SSH工具: [$perl_ssh]";
	say BOLD YELLOW "\t备份名后缀: [$back_suffix]";
	say BOLD YELLOW "\t远程项目根目录: [$remote_root_dir]";
	say BOLD YELLOW "\t远程临时目录: [$remote_tmp_dir]";
	say BOLD YELLOW "\t存在更新的服务列表: [@services]\n";
	if ($opt_value eq "parser") {
		prepare_parser();
	}elsif($opt_value eq "check"){
		prepare_check();
	}elsif ($opt_value eq "upload") {
		prepare_upload();
	}elsif ($opt_value eq "backup") {
		prepare_backup();
	}elsif ($opt_value eq "update") {
		prepare_update();
	}elsif ($opt_value eq "clear") {
		prepare_clear();
	}elsif ($opt_value eq "restore") {
		prepare_restore();
	}elsif ($opt_value eq "all") {
		prepare_all();
	}elsif ($opt_value eq "ssh-key") {
		prepare_key();
	}elsif ($opt_value eq "test"){
                test();
	}else {
		print_help();
	}
}

sub exec_command{
	my $command = shift;
	my $remote_command;
	if($perl_ssh){
     		# 使用perl插件
	 	$remote_command = "atnodes -u $user_name \"$command\" $host";
	}else{
	  	# ssh centos@bjim 执行原生命令
	  	$remote_command = "ssh $user_name\@$host \"$command\"";
	}
	say BOLD YELLOW "\t执行remote命令: $remote_command";
	my $command_exec = `$remote_command`;
	return $command_exec;
}

sub upload_comand {
   my ($sourceFile,$targetDir) = @_;
   my $remoteDir = "$remote_tmp_dir$targetDir";
   say BOLD BLUE "\t待执行upload命令[$sourceFile]-->[$remoteDir]";
   create_remote_dir("$remoteDir");
   my $remote_command;
   if ($perl_ssh){
        $remote_command = "tonodes -L $sourceFile -u $user_name \"$host\":$remoteDir/";
   }else {
        $remote_command = "scp -r $sourceFile $user_name\@$host:$remoteDir/";
   }
   #if ($ssh){
   #$remote_command = "tonodes -L $sourceFile -u $user_name \"$host\":$remoteDir/";
   #}else{
   #	$remote_command = "tonodes -w -L $sourceFile -u $user_name \"$host\":$remoteDir/";
   #}
   say BOLD BLUE "\t执行upload命令[$remote_command]";
   my $command_exec = `$remote_command`;
}

sub prepare_key {
	unless ($perl_ssh){
	        say BOLD RED "请先安装Perl SSH插件\n";
                return;
	}
	unless ($host){
		say BOLD RED "请使用[-host]命令行参数配置远程主机名\n";
		return;
	}
	unless ($user_name) {
		say BOLD RED "请使用[-user]命令行参数配置远程主机用户名\n";
                return;
	}
	say BOLD RED "[配置SSH免密钥登陆]: 请根据提示输入用户[$user_name]对应的远程服务器[$host][密码]";
	my $remote_command = "key2nodes -u $user_name $host";
	my $command_exec = `$remote_command`;
}

sub create_remote_dir {
	my $dirName = shift;
	exec_command("mkdir -p $dirName");
}

sub create_remote_tmp_dir {
	exec_command("mkdir -p $remote_tmp_dir");
}

sub clear_remote_tmp_dir {
	exec_command("rm -rf $remote_tmp_dir*");
}
sub remove_remote_tmp_dir {
	exec_command("rm -rf $remote_tmp_dir");
}

sub test {
	say BOLD GREEN "[测试]准备环境....";
	remove_remote_tmp_dir();
	say BOLD GREEN "[测试]执行远程命令...";
	exec_command("mkdir -p $remote_tmp_dir"."test_001/test/dir");
	say BOLD GREEN "[测试]上传文件...";
	my $sourceFile = "/etc/hosts";
	upload_comand($sourceFile,"test_001/test/dir");
	say BOLD GREEN "[测试]清理环境...";
	remove_remote_tmp_dir();
}

sub prepare_parser{
   unless (-d $project_root_dir){
         say BOLD RED "源目录[$project_root_dir]不存在，请检查!";
         return;
   }
   while(<DATA>){
    	next if $_ =~ /^#/;
	next if $_ =~ /^$/;
	my $full_file_name = "$project_root_dir$_";
	chomp $full_file_name;
	unless (-f $full_file_name){
	   die "the $full_file_name is not a file!"
	}
	my ($file_name, $file_path) = fileparse($_);
	$upload_file_hash{$full_file_name} = $file_path;
    }
    unless (upload_file_num() > 0){
        say BOLD RED "没有需要更新的文件!";
        return;
    }
    print_upload_file_hash();
}

sub prepare_check {
   say BOLD GREEN "[检测]是否存在未清理的备份文件...";
   my $rs = exec_command("find $remote_root_dir -name *.$back_suffix");
   say $rs;
}

sub prepare_upload {
    prepare_parser();
    exec_upload_file();
}

sub prepare_backup {
    prepare_parser();
    exec_backup_file();
}

sub prepare_update {
    prepare_parser();
    exec_backup_file();
    exec_update_file();
}

sub prepare_clear {
   prepare_parser();
   exec_clear_backup_file();
   clear_remote_tmp_dir();
}

sub prepare_all {
   prepare_parser();
   exec_upload_file();
   exec_backup_file();
   exec_update_file();
   say BOLD RED "[提示]更新完成,确认无误后,需要手动执行: clear命令进行清理";
}

sub prepare_restore {
	prepare_parser();
	exec_backup_file();
	exec_restore_file();
}

sub exec_restore_file {
	while (my($local_source_file,$relative_dir) = each %upload_file_hash) {
               my ($file_name, $file_dir) = fileparse($local_source_file);
               my $remote_source_dir = "$remote_root_dir$relative_dir";
               my $remote_source_file = "$remote_source_dir$file_name";
               my $back_file = "$remote_source_file.$back_suffix";
               exec_command("rm -rf $remote_source_file");
               say BOLD RED "[还原文件]: [$back_file]-->[$remote_source_file]";
               exec_command("mv $back_file $remote_source_file");
        }
}

sub upload_file_num {
    my @hash_key = keys %upload_file_hash;
    my $length = @hash_key;
    return $length;
}

sub print_upload_file_hash {
	my $length = upload_file_num();
	say BOLD GREEN "hi, 本次需要更新以下文件[$length]:";
	while (my($key,$value) = each %upload_file_hash) {
		say "\t[$key] -> [$value]";
	}
}

sub exec_upload_file {
	say BOLD MAGENTA "清理远程[临时目录: $remote_tmp_dir]...";
	clear_remote_tmp_dir();
	say BOLD GREEN "开始上传[更新文件]....";
	while (my($local_source_file,$remote_dir) = each %upload_file_hash) {
               upload_comand($local_source_file,$remote_dir);
        }
}

sub exec_backup_file {
    while (my($local_source_file,$relative_dir) = each %upload_file_hash) {
               my ($file_name, $file_dir) = fileparse($local_source_file);
	       my $remote_source_dir = "$remote_root_dir$relative_dir";
    	       my $remote_source_file = "$remote_source_dir$file_name";
	       my $back_file = "$remote_source_file.$back_suffix";
	       exec_command("mkdir -p $remote_source_dir");
	       say BOLD RED "备份文件[不覆盖存在的文件]: [$remote_source_file]-->[$back_file]";
	       exec_command("cp -n $remote_source_file $back_file");
    }
}

sub exec_update_file {
    while (my($local_source_file,$relative_dir) = each %upload_file_hash) {
               my ($file_name, $file_dir) = fileparse($local_source_file);
               my $remote_source_dir = "$remote_root_dir$relative_dir";
	       my $remote_tmp_file = "$remote_tmp_dir$relative_dir$file_name";
               say BOLD RED "更新文件: [$remote_tmp_file]-->[$remote_source_file]";
               exec_command("cp -u $remote_tmp_file $remote_source_dir");
    }
}

sub exec_clear_backup_file {
    while (my($local_source_file,$relative_dir) = each %upload_file_hash) {
               my ($file_name, $file_dir) = fileparse($local_source_file);
               my $remote_source_dir = "$remote_root_dir$relative_dir";
               my $remote_source_file = "$remote_source_dir$file_name";
               my $back_file = "$remote_source_file.$back_suffix";
               say BOLD RED "清理备份文件: [$back_file]";
               exec_command("rm -rf $back_file");
    }
}


########## 待更新文件的相对路径(编辑区) ########
# 本地项目根目录 + 待更新文件的相对路径 = 完整的本地文件路径
# my $project_root_dir = "/Users/limengyu/IdeaProjects/iron_chat_service/";

__DATA__
# 刪除群成員
#services/galley/src/Galley/API.hs
#services/galley/src/Galley/API/Update.hs
# 修改群創建
#services/galley/src/Galley/API/Create.hs
#services/galley/src/Galley/Intra/Group.hs
#services/galley/src/Galley/Intra/Util.hs
