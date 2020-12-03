#!/usr/bin/expect -f

#定义堡垒机账号/密码/IP

set target [lindex $argv 1]
set salt [lindex $argv 0]
set user "用户名"
set passwd "密码"
set bastion_host "目标地址ip"

	#执行ssh操作，登陆到堡垒机
	spawn ssh $user@$bastion_host
	#检测命令行的返回信息，匹配password关键字
	expect "*password:"	
	#自动输入密码 回车
	send "$passwd$salt\r"
	#没有参数直接返回终端
	if { $argc == 0 } {
		interact
		exit 1
	}
	#监测命令行的返回信息，匹配下面关键字
	expect "Opt or Host>:"
	#发送登录的机器
	send "3\r"
	#检测命令行的返回信息，匹配password关键字
	expect "Opt or Host>:"
	#自动输入密码 回车
	send "$target\r"
	expect "]*"
	send "sudo -s\r"
	expect "]*"
	send "su admin\r"
	#自动交互
	interact
