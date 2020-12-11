#!/usr/bin/ruby
# -*- coding: UTF-8 -*-

require 'Find'
require 'open3'
require 'net/https'
require 'uri'
require 'json'
require 'cocoapods'

$REPO_SOURCE = 'git@git.gametaptap.com:tds/client-sdk/tds-sdk-all/tdsspecs.git'
$REPO_NAME = 'tdsspecs'
$GIT_SOURCE = 'git@git.gametaptap.com:tds/client-sdk/tds-sdk-all/tds-all-libs-ios'
$PATH = "/Users/#{ENV['USER']}/Documents"

$USE_ORIGIN
$SPEC_NAME
$SHELL_TYPE

def syscall cmd, msg = 'PP-ERROR', a_exit = true, a_verbose = true
    cmd = a_verbose ? "#{cmd} --verbose" : cmd
    stdout, stdeerr, status = Open3.capture3(cmd)
    if status.success?
        puts "#{cmd}:#{stdout}" if stdout.length > 0
    else
        puts "#{cmd}(#{msg}):#{stdeerr}"
        if a_exit
            exit
        end
    end
    stdout
end

def matchPodspecFile path
    specPath = Dir["#{path}/*.podspec"]
    if specPath.length == 1
        specPath[0]
    else
        puts "匹配podspec文件失败：目标路径的一级目录中，podspec文件检索异常：#{specPath}"
        exit
    end
end

# check repo files
def c_repo_files p
    puts "正在校验仓库文件"
    puts "..."
    # check CHANGELOG
    if !(Dir["#{p}/CHANGELOG.md"].length > 0)
        syscall "cd #{p} && touch CHANGELOG.md", "创建CHANGELOG失败", true, false
    end
    # check README
    if !(Dir["#{p}/README.md"].length > 0)
        syscall "cd #{p} && touch README.md", "创建README失败", true, false
    end
    # check .gitignore
    File.open("#{p}/.gitignore", "w+") { |f|
        uri = URI("https://www.toptal.com/developers/gitignore/api/xcode,objective-c,cocoapods,macos,swift")
        res = Net::HTTP.get_response(uri)
        f << res.body
        f << "\n*-*/"
    }
    # check podspec

    ## alter target_xcconfig with simulator/arm64
    s_p = matchPodspecFile p
    file = File.open(s_p)
    if not File.writable? s_p then
        #check out the file first
        file = File.open(s_p).chmod(0755)
    end
    file_s = file.read 
    s = " 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' "
    pattern = /s.pod_target_xcconfig\s*=\s*{\K[^}]*/m
    result = file_s.scan(pattern)
    buffer = file_s
    if result.length == 0
        lines = IO.readlines file
        lines[-2] << "  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }\n  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }\n"
        buffer = lines.join ""
    else
        buffer = file_s.gsub(pattern, s).gsub(/s.user_target_xcconfig\s*=\s*{\K[^}]*/m, s)
    end
    File.write(s_p, buffer)
end

# sync repo files
# 
def sync_repo_files r_p, s_p, f_n
    puts "正在更新framework仓："
    puts "..."
    # 迁移framework
    rp = r_p + "/#{f_n}.framework"
    f_p = "#$PATH/#{f_n}"
    t_p = "#{f_p}/#{f_n}"
    syscall "rm -rf #{t_p} && mkdir #{t_p} && cp -R #{rp} #{t_p}/#{f_n}.framework && rm -rf #{File.expand_path("..", r_p)}", "迁移#{rp}失败", true, false
    # 更新版本  
    specP = matchPodspecFile f_p
    ver = alterVersion specP, getVersion(s_p)
    # 同步podspec
    fs,ls = ''
    File.open(s_p) {|f|
        f.each_line do |l|
            fs = l if l.include? 's.frameworks'
            ls = l if l.include? 's.library'
        end
    }
    buffer = ''
    File.open(specP) {|f|
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
    File.write(specP, buffer)
end

def cloneGit(n)
    git = "#$GIT_SOURCE/#{n}.git"
    syscall "cd #$PATH && rm -rf #{n} && git clone #{git}", "拉取仓库失败(#{git})"
    git
end

def gitam (path, note)
    syscall "cd #{path} && git add . && git commit -m \"#{note}\" && git push", "提交代码失败"
end

def gittag(path, tag)
    syscall "cd #{path} && git tag #{tag} && git push --tags", "打Tag失败"
end

def findLocalRepoSource
    stdout = syscall "pod repo list", "获取本地pod源列表失败"
    repos = stdout.split(/\n/)
    hasRepo = 0
    repos.each do |repo|
        if repo.include?$REPO_SOURCE
            index = repos.index(repo) - 2
            $REPO_NAME = repos[index].strip
            hasRepo = 1
            break
        end
    end
    if !hasRepo
        syscall "pod repo add #$REPO_NAME #$REPO_SOURCE", "添加私有源失败"
    end
    $REPO_NAME
end

def updateLocalRepoSource
    puts "正在更新本地源:#{findLocalRepoSource}......"
    syscall "pod repo update #$REPO_NAME", "更新 #$REPO_NAME 失败"
end

def getVersion specP
    file = File.read specP 
    pattern = /s.version\s*=\s*'\K[^']*/m
    result = file.scan(pattern)[0]
    result
end

def get_timestamp
    Time.new.strftime("%Y%m%d%H%M")[2, 10]
end

def alterVersion specP, version
    file = File.read specP 
    pattern = /s.version\s*=\s*'\K[^']*/m
    result = file.scan(pattern)
    if !(result.length > 0)
        pattern = /s.version\s*=\s*"\K[^"]*/m
        result = file.scan(pattern)
        if !(result.length > 0)
            puts "匹配#{specP} version失败"
            exit
        end
    end
    if version == '0'
        # 本地打包，不指定version
    elsif version == '-1'
        # 自增版本 
        vers = result[0].split('.')
        ver = result[0]
        t_stamp = get_timestamp
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
        if not File.writable? specP then
            #check out the file first
            File.open(specP).chmod(0755)
        end
        file = File.write(specP, buffer)
        result = [ver]
    else 
        # 指定版本
        buffer = file.gsub pattern, version
        if not File.writable? specP then
            #check out the file first
            File.open(specP).chmod(0755)
        end
        file = File.write(specP, buffer)
        result = [version]
    end
    result[0]
end

def podPackage path, name
    syscall "cd #{path} && pod package #{name} --force", "打包失败"
end

def replacePackageSource path, origin
    cnt = ""
    if origin
        cnt = " :git => '#$GIT_SOURCE/#$SPEC_NAME.git', :tag => s.version.to_s"
    else
        cnt = " :git => '#{File.expand_path("..", path)}'"
    end

    file = File.read path
    pattern = /s.source\s*=\s*{\K[^}]*/m
    if file.scan(pattern).length > 0
        buffer = file.gsub pattern, cnt
        if not File.writable? path then
            #check out the file first
            File.open(path).chmod(0755)
        end
    file = File.write(path, buffer)
    end
end

def replacePackageName p, s
    file = File.read p
    pattern = /s.name\s*=\s*'\K[^']*/m
    sn = file.scan(pattern)
    if sn.length > 0
        sn = sn[0]
        buffer = file.gsub pattern, s ? (
            if !sn.include?"Source"
                sn = sn + "Source"
            end
            sn
        ) : (
            if sn.include?"Source"
                sn = sn.gsub /Source/, ''
            else
                sn = sn
            end
            sn 
        )
        if not File.writable? p then
            #check out the file first
            File.open(p).chmod(0755)
        end
        file = File.write(p, buffer)
    end
    sn
end

def publish_f r_p, s_p, f_n
    puts "正在拉取远端framework仓:#{f_n}："
    puts "..."
    cloneGit "#{f_n}"
    c_repo_files "#$PATH/#{f_n}"
    sync_repo_files r_p, s_p, f_n
    f_p = "#$PATH/#{f_n}"
    ver = getVersion s_p
    puts "正在提交代码..."
    gitam "#{f_p}", "#{ver} Updated"
    gittag "#{f_p}", ver
    puts "正在远端验证..."
    specP = matchPodspecFile f_p
    syscall "pod repo push #$REPO_NAME #{specP} --use-libraries --allow-warnings", "发版失败:#{f_n} #{ver}"
    puts "已成功发版#{f_n} #{ver}"
end

def publish (r_p, s_p, f_n)
    puts "是否发版?(Y/N)："
    flag = gets.strip
    case flag
    when "Y","y"
        puts '请输入版本（e.g. 1.3.2-unstable），`-1`表示自动：'
        ver = gets.strip
        puts "正在更新podspec文件..."
        # 更新PodName
        replacePackageName s_p, true
        # 更新版本号
        ver = alterVersion s_p, ver
        # 更新source
        replacePackageSource s_p, true
        file = File.read s_p
        puts file
        puts "正在提交代码..."
        gitam "#$PATH/#$SPEC_NAME", "#{ver} Updated"
        gittag "#$PATH/#$SPEC_NAME", ver
        puts "正在远端验证..."
        syscall "pod repo push #$REPO_NAME #{s_p} --allow-warnings", "发版失败:#$SPEC_NAME #{ver}"
        puts "已成功发版#$SPEC_NAME #{ver}"
        publish_f r_p, s_p, f_n
    when "N","n"
        syscall "open #{r_p}", "打开包地址失败", true, false
    else
        puts 'Illegal pargram.'
        publish r_p, s_p, f_n
    end
end

def packageOrigin git
    c_repo_files "#$PATH/#$SPEC_NAME"
    puts "正在使用远端代码打包(#$SPEC_NAME):#{git}"
    puts '...'
    specP = matchPodspecFile "#$PATH/#$SPEC_NAME"
    specN = specP.split('/').at -1
    replacePackageSource specP, true
    n = replacePackageName specP, false
    repoP = "#$PATH/#$SPEC_NAME"
    podPackage repoP, specN
    resultP = "#{repoP}/#{n}-#{getVersion(specP)}/ios"
    puts "远端代码打包完成(#{resultP})"
    publish resultP, specP, n
end

def packageLocal path
    c_repo_files "#{path}"
    specP = matchPodspecFile path
    specN = specP.split('/').at -1
    $SPEC_NAME = specN.split('.').at 0
    puts "正在使用本地代码打包:#{specN}"
    puts '...'
    replacePackageSource specP, false
    n = replacePackageName specP, false
    podPackage path, specN
    resultP = "#{File.expand_path("..", specP)}/#{n}-#{getVersion(specP)}/ios"
    puts "本地代码打包完成(#{resultP})"
    publish resultP, specP, n
end

def package
    # 更新本地源
    updateLocalRepoSource
    # 打包
    if $USE_ORIGIN
        # 获取包名、版本号
        puts '请输入仓库名（e.g. tdsmomentsource）：'
        $SPEC_NAME = gets.strip
        # 拉取远端仓库
        puts "正在拉取远端仓库源码:#$SPEC_NAME"
        packageOrigin cloneGit $SPEC_NAME
    else
        # 获取本地地址
        puts '请输入本地仓库地址（e.g. /Users/jocer/Documents/tdstapdbsource）：'
        path = gets.strip
        packageLocal path
    end
end

def s_gem_l n
    g_out = syscall 'gem list --local', '拉取gem列表失败'
    l_gems = g_out.split(/\n/)
    r = false
    l_gems.each do |g|
        if g.include? n
            r = true
            break
        end
    end
    if !r
        puts "gem未安装#{n},ruby当前版本是#{syscall('ruby -v', '获取ruby版本失败')}"
        puts "继续在homebrew中检索#{n}..."
        r = syscall("brew search #{n}", "homebrew未安装#{n}", false).length > 0 ? true : false
        if r 
            puts "homebrew已安装#{n}"
        end
    else
        puts "gem已安装#{n}"
    end
    r
end

def c_install n
    r = s_gem_l n
    if !r
        puts "未安装#{n}，输入安装方式（gem/homebrew）："
        install = gets.strip
        case install
        when 'gem'
            puts "正在安装#{n}:`sudo gem install #{n}`"
            syscall "sudo gem install #{n}", "安装#{n}失败"
        when 'homebrew'
            puts "正在安装#{n}:`brew install #{n}`"
            syscall "brew install #{n}", "安装#{n}失败"
        end
    end
    r
end

def main 
    puts '前置检查...'
    c_install 'cocoapods'
    c_install 'cocoapods-packager'
    puts '使用远端代码打包？（Y/N）：'
    useOrigin = gets.strip
    case useOrigin
    when "Y","y"
        $USE_ORIGIN = true
    when "N","n"
        $USE_ORIGIN = false
    else
        puts 'Illegal pargram.'
        main
    end
    package
end

main


#
# Be sure to run `pod lib lint TapSDK.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
    s.name             = 'TapSDK'
    s.version          = '0.1.0'
    s.summary          = 'A SDK build by TapTap Developer Service team'
    s.platform         = :ios, '9.0'
    s.description      = <<-DESC
    TODO: Add long description of the pod here.
                         DESC
    s.homepage         = 'https://github.com/Jocer/TapSDK'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'tds-developer' => 'tds-developer@xd.com' }
    s.source           = { :git => '/Users/jocer/Desktop/TapSDK'}
    s.ios.deployment_target = '8.0'
    s.default_subspec = 'Core'
    s.source_files = 'TapSDK/Classes/**/*'
    s.public_header_files = 'TapSDK/Classes/**/Public/**/*.h'
    s.subspec 'Core' do |ss|
        ss.source_files = 'TapSDK/Classes/Core/**/*'
        ss.public_header_files = 'TapSDK/Classes/Core/Public/**/*.h'
        ss.resource_bundles = {
            'Core' => ['TapSDK/Resources/Core/**/*']
        }
        ss.dependency 'TapSDK/TestA'
        ss.dependency 'TapSDK/TestB'
        ss.dependency 'TapSDK/TestC'
    end
    s.subspec 'TestA' do |ss|
        ss.source_files = 'TapSDK/Classes/TestA/**/*'
        ss.public_header_files = 'TapSDK/Classes/TestA/Public/**/*.h'
        ss.resource_bundles = {
            'TestA' => ['TapSDK/Resources/TestA/**/*']
        }
        ss.frameworks = 'UIKit', 'CoreFoundation'
    end
    s.subspec 'TestB' do |ss|
        ss.source_files = 'TapSDK/Classes/TestB/**/*'
        ss.public_header_files = 'TapSDK/Classes/TestB/Public/**/*.h'
        ss.resource_bundles = {
            'TestB' => ['TapSDK/Resources/TestB/**/*']
        }
        ss.libraries = 'c++'
    end
    s.subspec 'TestC' do |ss|
        ss.source_files = 'TapSDK/Classes/TestC/**/*'
        ss.public_header_files = 'TapSDK/Classes/TestC/Public/**/*.h'
        ss.resource_bundles = {
            'TestC' => ['TapSDK/Resources/TestC/**/*']
        }
        ss.frameworks = 'SystemConfiguration'
        ss.dependency 'TapSDK/TestA'
    end
    s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
    s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end
