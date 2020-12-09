#!/usr/bin/ruby
# -*- coding: UTF-8 -*-

$REPO_PATH = ARGV[0]
$GIT_SOURCE = 'git@git.gametaptap.com:tds/client-sdk/tds-sdk-all/tds-all-libs-ios'
$SPEC_PATH = Dir["#$REPO_PATH/*.podspec"][0]
$SPEC_NAME = $SPEC_PATH.split('/').at -1
$SPEC_NAME = $SPEC_NAME.split('.').at -2
$PATH = "/Users/#{ENV['USER']}/Documents"
$ORI_SPEC_PATH = Dir["#$PATH/#$SPEC_NAME/**/*.podspec"][0]

def get_version path
    file = File.read path
    pattern = /s.version\s*=\s*'\K[^']*/m
    result = file.scan(pattern)
    if !(result.length > 0)
        pattern = /s.version\s*=\s*"\K[^"]*/m
        result = file.scan(pattern)
        if !(result.length > 0)
            puts "匹配#{path} version失败"
            exit
        end
    end
    result[0]
end

def sync_version
    file = File.read $SPEC_PATH 
    pattern = /s.version\s*=\s*"\K[^"]*/m
    result = file.scan(pattern)
    ver = get_version($ORI_SPEC_PATH)
    if result.length > 0
        buffer = file.gsub pattern, ver
        if not File.writable? $SPEC_PATH  then
            File.open($SPEC_PATH ).chmod(0755)
        end
        file = File.write($SPEC_PATH , buffer)
    end
    ver
end

def sync_configs
    fs,ls = ''
    File.open($ORI_SPEC_PATH) {|f|
        f.each_line do |l|
            fs = l if l.include? 's.frameworks'
            ls = l if l.include? 's.library'
        end
    }
    buffer = ''
    File.open($SPEC_PATH) {|f|
        f.each_line do |l|
            if l.include? 's.frameworks'
                buffer += fs
            elsif l.include? 's.library'
                buffer += ls
            else
                buffer += l
            end
        end
    }
    File.write($SPEC_PATH, buffer)
end

def repo_commit v
    Dir.chdir $REPO_PATH
    system "git add . && git commit -m 'Version Updated:#{v}' && git tag -a #{v} -m '#{v}' "
end

def sync_framework
    resultP = "#{File.expand_path("..", $ORI_SPEC_PATH)}/ios/#$SPEC_NAME.framework"
    targetP = "#$REPO_PATH/#$SPEC_NAME/"
    if File::directory?(targetP)
        system "rm -rf #{targetP}"
    end
    Dir.mkdir(targetP)
    system "cp -R #{resultP} #{targetP}/#$SPEC_NAME.framework && rm -rf #{resultP}"
end

def sync
    sync_configs
    sync_framework
    repo_commit(sync_version) 
end

sync