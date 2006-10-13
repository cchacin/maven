#!/usr/bin/perl

$dirname = "maven-core-it";
$newITs = "maven-core-it-new";

open( FILE, "$dirname/integration-tests-descriptions.txt" ) or die;
undef $/;
$readme = <FILE>; 
close( FILE );

@descriptions = $readme =~ m/(it\d+\: .*?)(?=\nit\d+\:|$)/gsx;
for $desc (@descriptions) {
	($name, $value) = ($desc =~ m/^(it\d+)\: (.*)$/s);
	chomp ($value);
	$comment{$name} = $value;
}
    
system( "rm -rf $newITs" );    
    
opendir(DIR, $dirname) or die "can't opendir $dirname: $!";
while (defined($filename = readdir(DIR))) {
    next unless (-d "$dirname/$filename");
    next if ($filename eq ".svn");
    next unless ($filename =~ m/^it0\d+$/);
    $filePrebuildHook = "$dirname/$filename/prebuild-hook.txt";
    $fileCliOptions = "$dirname/$filename/cli-options.txt";
    $fileSystemProperties = "$dirname/$filename/system.properties";
    $fileVerifierProperties = "$dirname/$filename/verifier.properties";
    $fileGoals = "$dirname/$filename/goals.txt";
    $fileExpectedResults = "$dirname/$filename/expected-results.txt";
    $failOnErrorOutput = 1;
    if (!exists($comment{$filename})) {
    	die "no comment: $filename\n";
    }
    
    $itBaseDirectory = "$newITs/$filename";
    $itTestCaseDirectory = "$itBaseDirectory/src/test/java/org/apache/maven/it";    
    $testFile = "$itTestCaseDirectory/MavenIntegrationTest_$filename" . ".java";    
    $testProjectDirectory = "$itBaseDirectory/src/test-project";
    
    system( "mkdir -p $itTestCaseDirectory" );
    system( "cp -r $dirname/$filename $testProjectDirectory" );
	system( "rm $testProjectDirectory/cli-options.txt > /dev/null 2>&1" );
	system( "rm $testProjectDirectory/system.properties > /dev/null 2>&1" );
	system( "rm $testProjectDirectory/verifier.properties > /dev/null 2>&1" );
	system( "rm $testProjectDirectory/goals.txt > /dev/null 2>&1" );
	system( "rm $testProjectDirectory/expected-results.txt > /dev/null 2>&1" );
	system( "rm $testProjectDirectory/log.txt > /dev/null 2>&1" );
    
    print $testFile . "\n";
    open( T, "> $testFile") or die;
    print $filename . "\n";    
    print T "package org.apache.maven.it;\n";
    print T "import java.io.File;\n";
    print T "public class MavenIntegrationTest${filename} /*extends AbstractMavenIntegrationTest*/ {\n";    
    print T "/** $comment{$filename} */\n";
    print T "public void test_$filename() throws Exception {\n";
    print T "String rootdir = System.getProperty(\"rootdir\");\n";
    print T "File basedir = new File(rootdir, \"$filename\");\n";
    print T "Verifier verifier = new Verifier(basedir.getAbsolutePath());\n";
    
    if (-e "$filePrebuildHook") {
    	open (FILE, "$filePrebuildHook");
	    while ($line = <FILE>) {
	    	if ($line =~ /^(rm|rmdir) (.*)/) {
	    		($cmd, $path) = ($1, $2);
	    		
	    		if ($cmd eq "rm") {
	    			if ($path =~ m/^\$\{artifact:([^:]*?):([^:]*?):([^:]*?):([^:]*?)\}$/) {
	    				print T "verifier.deleteArtifact(\"$1\", \"$2\", \"$3\", \"$4\");\n";
	    			} else {
	    				print T "FileUtils.deleteFile(new File(basedir, \"$path\"));\n";
	    			}
	    		} elsif ($cmd eq "rmdir") {
	    			print T "FileUtils.deleteDirectory(new File(basedir, \"$path\"));\n";
	    		} else {
	    			die ("wtf? $line\n");
	    		}
			}
			else {
				die ("unexpected command: $line\n");
			}
	    }
	    close FILE;
	}
    
    if (-e "$fileCliOptions") {
    	open(FILE, $fileCliOptions);
    	$cliOptions = <FILE>;
    	chomp ($cliOptions);
    	$cliOptions =~ s/"/\\"/g;
    	print T "List cliOptions = new ArrayList();\n";
    	print T "cliOptions.add(\"$cliOptions\");\n";
    	print T "verifier.setCliOptions(cliOptions);\n";
    	close FILE;
    }
    if (-e "$fileSystemProperties") {
    	open(FILE, $fileSystemProperties);
    	print T  "Properties systemProperties = new Properties();\n";
    	while ($line = <FILE>) {
    		next if ($line =~ m/^\s*\#/);
    		($name, $value) = ($line =~ m/^([^=]*)=(.*)/);
    		print T  "systemProperties.put(\"$name\", \"$value\");\n";
    	}
    	print T  "verifier.setSystemProperties(systemProperties);\n";
    	close FILE;
    }
    if (-e "$fileVerifierProperties") {
    	open(FILE, $fileVerifierProperties);
    	print T  "Properties verifierProperties = new Properties();\n";
    	while ($line = <FILE>) {
    		next if ($line =~ m/^\s*\#/);
    		($name, $value) = ($line =~ m/^([^=]*)=(.*)/);
    		if ($name eq "failOnErrorOutput" and $value eq "false") {
    			$failOnErrorOutput = 0;
    		}
    		print T  "verifierProperties.put(\"$name\", \"$value\");\n";
    	}
    	print T  "verifier.setVerifierProperties(verifierProperties);\n";
    	close FILE;
    }
    
    open (FILE, $fileGoals) or die "Couldn't open $fileGoals: $!\n";
    
    @goals = ();
    while ($line = <FILE>) {
    	next if ($line =~ m/^\s*$/);
    	chomp ($line);
    	push (@goals, $line);
    }
    if (scalar(@goals) == 1) {
    	print T  "verifier.executeGoal(\"$goals[0]\");\n";
    } else {
	    print T  "List goals = Arrays.asList(new String[] {";
	    for ($i = 0; $i < @goals; $i++) {
	    	print T  "\"$goals[$i]\"";
	    	print T  ", " if ($i != scalar(@goals) -1);
		}
	    print T  "});\n";
	    print T  "verifier.executeGoals(goals);\n";
	}
	
	close FILE;
	
	if (-e $fileExpectedResults) {
	
		open (FILE, $fileExpectedResults) or die "Couldn't open $fileExpectedResults: $!\n";
		
		while ($line = <FILE>) {
	    	chomp ($line);
	    	#print T  ("OLDLINE: $line\n");
	    	if ($line =~ /^\#(.*)/) {
	    		print T  "//$1\n";
	    		next;
	    	}
	    	if ($line =~ m/^\!\$\{artifact:([^:]*?):([^:]*?):([^:]*?):([^:]*?)\}$/) {
	    		print T  "verifier.assertArtifactNotPresent(\"$1\", \"$2\", \"$3\", \"$4\");\n";
	    	} elsif ($line =~ m/^\$\{artifact:([^:]*?):([^:]*?):([^:]*?):([^:]*?)\}$/) {
	    		print T  "verifier.assertArtifactPresent(\"$1\", \"$2\", \"$3\", \"$4\");\n";
	    	} elsif ($line =~ m/^\!(.*)/) {
	    		print T  "verifier.assertFileNotPresent(\"$1\");\n";
	    	} else {
	    		print T  "verifier.assertFilePresent(\"$line\");\n";
	    	}
	    }
	    close FILE;
	}
	
	if ($failOnErrorOutput) {
		print T  "verifier.verifyErrorFreeLog();\n";
	} else {
		print T  "// don't verify error free log\n";
	}
	print T  "}}\n\n";
	
}
        
print T  $postamble;        
        
closedir(DIR);
