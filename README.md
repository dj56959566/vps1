# Djkyc Hysteria2 安装/卸载脚本

这是一个用于安装和卸载 Hysteria2 的一键脚本，具有全绿色界面显示和友好的用户交互。

功能特点

全绿色界面，视觉效果统一美观

支持 Hysteria2 的安装与卸载

自动检测并支持 IPv4 和 IPv6 网络

提供多个对三网友好的域名选项

自动生成自签名证书

生成客户端配置信息和分享链接

提供二维码方便移动设备扫描使用

# 一键安装

```
bash <(curl -fsSL https://raw.githubusercontent.com/dj56959566/vps1/main/hy2.sh)
```

系统要求

Debian 10+ 系统

需要 root 权限

使用方法

交互式安装

直接运行一键安装命令，按照脚本提示进行操作：

选择安装或卸载

选择使用 IPv4 或 IPv6

设置端口号（默认 2096）

选择证书域名（提供多个对三网友好的选项）

设置密码（默认自动生成）

带参数安装

脚本支持带参数执行，省略交互过程：

```
bash <(curl -fsSL https://raw.githubusercontent.com/dj56959566/vps1/main/hy2.sh) [4|6] [端口] [域名] [密码]
```

参数说明：

第1个参数：4 表示使用 IPv4，6 表示使用 IPv6

第2个参数：端口号，范围 1-65535

第3个参数：证书域名

第4个参数：密码

例如：

bash <(curl -fsSL https://raw.githubusercontent.com/dj56959566/vps1/main/hy2.sh) 4 8443 www.apple.com mypassword

域名选项

脚本提供以下对三网友好的域名选项：

learn.microsoft.com (默认)

www.apple.com

www.bing.com

www.office.com

www.azure.com

www.amazon.com

www.linkedin.com

www.adobe.com

www.github.com

www.cloudflare.com

您也可以选择输入自定义域名。

客户端配置

安装完成后，脚本会显示客户端配置信息，包括：

服务器地址

端口

密码

TLS 设置

ALPN 设置

卸载
运行一键安装命令，选择卸载选项即可完全删除 Hysteria2 及其相关配置。

联系方式
如有问题，请通过电报联系：https://t.me/djkyc2_bot



