#!/usr/bin/ruby
# -*- coding: UTF-8 -*-

require 'open3'

$REPO_PATH = ARGV[0]
$GIT_SOURCE = 'git@git.gametaptap.com:tds/client-sdk/tds-sdk-all/tds-all-libs-ios'
$SPEC_PATH = Dir["#$REPO_PATH/*.podspec"][0]
$SPEC_NAME
$PATH = "/Users/#{ENV['USER']}/Documents"

def getVersion specP
    file = File.read specP 
    pattern = /s.version\s*=\s*'\K[^']*/m
    result = file.scan(pattern)[0]
    result
end

def replacePackageName
    file = File.read $SPEC_PATH
    pattern = /s.name\s*=\s*'\K[^']*/m
    sn = file.scan(pattern)
    if sn.length > 0
        sn = sn[0]
        if sn.include? "Source"
            sn = sn.gsub /Source/, ''
        end
        buffer = file.gsub pattern, sn
        if not File.writable? $SPEC_PATH then
            #check out the file first
            File.open($SPEC_PATH).chmod(0755)
        end
        file = File.write($SPEC_PATH, buffer)
    end
end

def package 
    stdout, stdeerr, status = Open3.capture3("pod package #$SPEC_PATH --force --verbose --spec-sources=git@git.gametaptap.com:tds/client-sdk/tds-sdk-all/tdsspecs.git")
    if status.success?
        puts "#{stdout}" if stdout.length > 0
    else
        puts "打包失败:#{stdeerr}, #{stdout}"
        exit
    end
end

def modify_podspec
    replacePackageName
end

def mv_result 
    resultP = "#{Dir.pwd}/#$SPEC_NAME-#{getVersion($SPEC_PATH)}"
    targetP = "#$PATH/#$SPEC_NAME"
    if File::directory?(targetP)
        system "rm -rf #{targetP}"
    end
    Dir.mkdir(targetP)
    system "cp -R #{resultP} #{targetP} && rm -rf #{resultP}"
end

def main
    $SPEC_NAME = $SPEC_PATH.split('/').at -1
    $SPEC_NAME = $SPEC_NAME.split('.').at -2
    $SPEC_NAME = $SPEC_NAME.gsub /Source/, ''
    modify_podspec
    package
    mv_result
end

main