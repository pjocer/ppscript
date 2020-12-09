#!/usr/bin/ruby
# -*- coding: UTF-8 -*-

$s_p = Dir["#{ARGV[0]}/*.podspec"][0]
$v_m = ARGV[1]

def repo_commit v
    system "cd #{ARGV[0]} && git add . && git commit -m 'package: #{v}' && git tag -a #{v} -m '#{v}' "
end

def modify_version
    file = File.read $s_p 
    pattern = /s.version\s*=\s*'\K[^']*/m
    result = file.scan(pattern)
    if !(result.length > 0)
        pattern = /s.version\s*=\s*"\K[^"]*/m
        result = file.scan(pattern)
        if !(result.length > 0)
            puts "匹配#{$s_p} version失败"
            exit
        end
    end
    if $v_m == '0'
        # 本地打包，不指定version
    elsif $v_m == '-1'
        # 自增版本 
        vers = result[0].split('.')
        ver = result[0]
        t_stamp = Time.new.strftime("%Y%m%d%H%M")[2, 10]
        if vers.size == 3
            vers << "#{t_stamp}"
            ver = vers.join '.'
        elsif vers.size == 4
            vers[3] = t_stamp
            ver = vers.join '.'
        else
            puts "当前版本号长度异常(#{result[0]})，请主动输入版本号："
            ver = gets.strip
        end
        buffer = file.gsub pattern, ver
        if not File.writable? $s_p then
            #check out the file first
            File.open($s_p).chmod(0755)
        end
        file = File.write($s_p, buffer)
        result = [ver]
    else 
        # 指定版本
        buffer = file.gsub pattern, $v_m
        if not File.writable? $s_p then
            #check out the file first
            File.open($s_p).chmod(0755)
        end
        file = File.write($s_p, buffer)
        result = [$v_m]
    end
    result[0]
end

repo_commit(modify_version)