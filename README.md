起初以为，在普及程度上，QUIC因为主要是Google主导，会曲高和寡。但是，查了一下，发现腾讯早在2017年就在生产环境应用了QUIC：<a href="https://zhuanlan.zhihu.com/p/32560981">让互联网更快的协议，QUIC在腾讯的实践及性能优化</a>. 结果显示：
<blockquote>灰度实验的效果也非常明显，其中 quic 请求的首字节时间 (rspStart) 比 http2 平均减少 326ms, 性能提升约 25%; 这主要得益于 quic 的 0RTT 和 1RTT 握手时间，能够更早的发出请求。

此外 quic 请求发出的时间 (reqStart) 比 h2 平均减少 250ms; 另外 quic 请求页面加载完成的时间 (loadEnd) 平均减少 2s，由于整体页面比较复杂, 很多其它的资源加载阻塞，导致整体加载完成的时间比较长约 9s，性能提升比例约 22%。</blockquote>
既然大厂都已经发车，我司也就可以考虑跟进了。稳妥起见，决定先在自己的博客开启QUIC，然后再逐步在线上业务进行推广。
<h2>方案概览</h2>
<img src="https://ws1.sinaimg.cn/large/44cd29dagy1fpevds3oi6j20ik07jgly.jpg" alt="" />

方案非常简单：不支持QUIC的浏览器依旧通过nginx tcp 443访问；支持QUIC的浏览器通过caddy udp 443访问。

由于nginx近期<a href="https://www.quora.com/When-will-nginx-add-support-for-QUIC">没有支持QUIC的计划</a>, 作为一名gopher, 因此这里选择<a href="https://github.com/mholt/caddy">caddy</a>作为QUIC的反向代理。后面会介绍caddy的具体安装和配置方法。

对于支持QUIC的浏览器来说，第一次访问支持QUIC的网站时，会有一次<code>服务发现</code>的过程。服务发现的流程在<a href="https://docs.google.com/document/d/1i4m7DbrWGgXafHxwl8SwIusY2ELUe8WX258xt2LFxPM/edit">QUIC Discovery
</a>有详细介绍。概括来说，主要有以下几步：
<ol>
 	<li>通过TLS/TCP访问网站，浏览器检查网站返回的http header中是否包含<code>alt-svc</code>字段。</li>
 	<li>如果响应中含有头部：<code>alt-svc: 'quic=":443"; ma=2592000; v="39"'</code>，则表明该网站的UDP 443端口支持QUIC协议，且支持的版本号是draft v39; max-age为2592000秒。</li>
 	<li>然后，浏览器会发起QUIC连接，在该连接建立前，http 请求依然通过TLS/TCP发送，一旦QUIC连接建立完成，后续请求则通过QUIC发送。</li>
 	<li>当QUIC连接不可用时，浏览器会采取5min, 10min的间隔检查QUIC连接是否可以恢复。如果无法恢复，则自动回落到TLS/TCP。</li>
</ol>
这里有一个比较坑的地方：对于同一个域名，TLS/TCP和QUIC必须使用相同的端口号才能成功开启QUIC。没有什么特殊的原因，提案里面就是这么写的。具体的讨论可以参见<a href="https://github.com/quicwg/base-drafts/issues/929">Why MUST a server use the same port for HTTP/QUIC?</a>

从上面QUIC的发现过程可以看出，要在网站开启QUIC，主要涉及两个动作：
<ol>
 	<li>配置nginx, 添加<code>alt-svc</code>头部。</li>
 	<li>安装和配置QUIC反向代理服务。</li>
</ol>
<h2>配置nginx, 添加<code>alt-svc</code>头部</h2>
一行指令搞定：
<div id="crayon-5c3cd5537f7b1943545948" class="crayon-syntax crayon-theme-turnwall crayon-font-monospace crayon-os-pc print-yes notranslate" data-settings=" minimize scroll-mouseover">
<div class="crayon-plain-wrap"></div>
<div class="crayon-main">
<table class="crayon-table">
<tbody>
<tr class="crayon-row">
<td class="crayon-nums " data-settings="show">
<div class="crayon-nums-content">
<div class="crayon-num" data-line="crayon-5c3cd5537f7b1943545948-1">1</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7b1943545948-2">2</div>
</div></td>
<td class="crayon-code">
<div class="crayon-pre">
<div id="crayon-5c3cd5537f7b1943545948-1" class="crayon-line"><span class="crayon-e">add_header </span><span class="crayon-v">alt</span><span class="crayon-o">-</span><span class="crayon-i">svc</span> <span class="crayon-s">'quic=":443"; ma=2592000; v="39"'</span><span class="crayon-sy">;</span></div>
<div id="crayon-5c3cd5537f7b1943545948-2" class="crayon-line crayon-striped-line"></div>
</div></td>
</tr>
</tbody>
</table>
</div>
</div>
<h2>安装QUIC反向代理服务器caddy</h2>
上面我们提到对于同一个域名，TLS/TCP和QUIC必须使用相同的端口号才能成功开启QUIC。然而，caddy服务器的QUIC特性无法单独开启，必须与TLS一起开启，悲剧的是TLS想要使用的TCP 443端口已经被nginx占用了

场面虽然有点尴尬，但是我们有docker：将caddy安装到docker中，然后只把本地的UDP 443端口映射到容器中即可。

于是我们创建了一个<a href="https://github.com/liudanking/docker-caddy">docker-caddy</a>项目。Dockerfile 10行内搞定：
<div id="crayon-5c3cd5537f7bd059285012" class="crayon-syntax crayon-theme-turnwall crayon-font-monospace crayon-os-pc print-yes notranslate" data-settings=" minimize scroll-mouseover">
<div class="crayon-plain-wrap"></div>
<div class="crayon-main">
<table class="crayon-table">
<tbody>
<tr class="crayon-row">
<td class="crayon-nums " data-settings="show">
<div class="crayon-nums-content">
<div class="crayon-num" data-line="crayon-5c3cd5537f7bd059285012-1">1</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7bd059285012-2">2</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7bd059285012-3">3</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7bd059285012-4">4</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7bd059285012-5">5</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7bd059285012-6">6</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7bd059285012-7">7</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7bd059285012-8">8</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7bd059285012-9">9</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7bd059285012-10">10</div>
</div></td>
<td class="crayon-code">
<div class="crayon-pre">
<div id="crayon-5c3cd5537f7bd059285012-1" class="crayon-line"><span class="crayon-e">FROM </span><span class="crayon-v">ubuntu</span><span class="crayon-o">:</span><span class="crayon-cn">16.04</span></div>
<div id="crayon-5c3cd5537f7bd059285012-2" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7bd059285012-3" class="crayon-line"><span class="crayon-e">LABEL </span><span class="crayon-v">maintainer</span><span class="crayon-o">=</span><span class="crayon-s">"liudanking@gmail.com"</span></div>
<div id="crayon-5c3cd5537f7bd059285012-4" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7bd059285012-5" class="crayon-line"><span class="crayon-e">RUN </span><span class="crayon-v">apt</span><span class="crayon-o">-</span><span class="crayon-e">get </span><span class="crayon-e">update</span></div>
<div id="crayon-5c3cd5537f7bd059285012-6" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7bd059285012-7" class="crayon-line"><span class="crayon-e">RUN </span><span class="crayon-v">set</span> <span class="crayon-o">-</span><span class="crayon-i">x</span><span class="crayon-h">  </span><span class="crayon-sy">\</span></div>
<div id="crayon-5c3cd5537f7bd059285012-8" class="crayon-line crayon-striped-line"><span class="crayon-h">    </span><span class="crayon-o">&amp;</span><span class="crayon-v">amp</span><span class="crayon-sy">;</span><span class="crayon-o">&amp;</span><span class="crayon-v">amp</span><span class="crayon-sy">;</span> <span class="crayon-v">apt</span><span class="crayon-o">-</span><span class="crayon-e">get </span><span class="crayon-e">install </span><span class="crayon-v">curl</span> <span class="crayon-o">-</span><span class="crayon-i">y</span> <span class="crayon-sy">\</span></div>
<div id="crayon-5c3cd5537f7bd059285012-9" class="crayon-line"><span class="crayon-h">    </span><span class="crayon-o">&amp;</span><span class="crayon-v">amp</span><span class="crayon-sy">;</span><span class="crayon-o">&amp;</span><span class="crayon-v">amp</span><span class="crayon-sy">;</span> <span class="crayon-e">curl </span><span class="crayon-v">https</span><span class="crayon-o">:</span><span class="crayon-c">//getcaddy.com | bash -s personal &amp;amp;&amp;amp; which caddy</span></div>
<div id="crayon-5c3cd5537f7bd059285012-10" class="crayon-line crayon-striped-line"></div>
</div></td>
</tr>
</tbody>
</table>
</div>
</div>
caddy 服务配置文件<code>/conf/blog.conf</code>:
<div id="crayon-5c3cd5537f7c1071249087" class="crayon-syntax crayon-theme-turnwall crayon-font-monospace crayon-os-pc print-yes notranslate" data-settings=" minimize scroll-mouseover">
<div class="crayon-plain-wrap"></div>
<div class="crayon-main">
<table class="crayon-table">
<tbody>
<tr class="crayon-row">
<td class="crayon-nums " data-settings="show">
<div class="crayon-nums-content">
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-1">1</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-2">2</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-3">3</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-4">4</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-5">5</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-6">6</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-7">7</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-8">8</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-9">9</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-10">10</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-11">11</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-12">12</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-13">13</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c1071249087-14">14</div>
<div class="crayon-num" data-line="crayon-5c3cd5537f7c1071249087-15">15</div>
</div></td>
<td class="crayon-code">
<div class="crayon-pre">
<div id="crayon-5c3cd5537f7c1071249087-1" class="crayon-line"><span class="crayon-v">https</span><span class="crayon-o">:</span><span class="crayon-c">//YOUR_DOMAIN</span></div>
<div id="crayon-5c3cd5537f7c1071249087-2" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7c1071249087-3" class="crayon-line"><span class="crayon-e">tls </span><span class="crayon-v">YOUR_CERT_KEY_DIR</span><span class="crayon-o">/</span><span class="crayon-v">chained</span><span class="crayon-sy">.</span><span class="crayon-e">pem </span><span class="crayon-v">YOUR_CERT_KEY_DIR</span><span class="crayon-o">/</span><span class="crayon-v">domain</span><span class="crayon-sy">.</span><span class="crayon-e">key</span></div>
<div id="crayon-5c3cd5537f7c1071249087-4" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7c1071249087-5" class="crayon-line"><span class="crayon-v">proxy</span> <span class="crayon-o">/</span> <span class="crayon-v">http</span><span class="crayon-o">:</span><span class="crayon-c">//VPS_PRIVATE_IP:81/ {</span></div>
<div id="crayon-5c3cd5537f7c1071249087-6" class="crayon-line crayon-striped-line"></div>
<div id="crayon-5c3cd5537f7c1071249087-7" class="crayon-line"><span class="crayon-e">header_upstream</span> <span class="crayon-e">Host</span> <span class="crayon-e">YOUR_DOMAIN</span></div>
<div id="crayon-5c3cd5537f7c1071249087-8" class="crayon-line crayon-striped-line"><span class="crayon-e">header_upstream</span> <span class="crayon-e">X</span><span class="crayon-o">-</span><span class="crayon-e">Real</span><span class="crayon-o">-</span><span class="crayon-e">IP</span> <span class="crayon-sy">{</span><span class="crayon-v">remote</span><span class="crayon-sy">}</span></div>
<div id="crayon-5c3cd5537f7c1071249087-9" class="crayon-line"><span class="crayon-e">header_upstream</span> <span class="crayon-e">X</span><span class="crayon-o">-</span><span class="crayon-e">Forwarded</span><span class="crayon-o">-</span><span class="crayon-st">For</span> <span class="crayon-sy">{</span><span class="crayon-v">remote</span><span class="crayon-sy">}</span></div>
<div id="crayon-5c3cd5537f7c1071249087-10" class="crayon-line crayon-striped-line"><span class="crayon-e">header_upstream</span> <span class="crayon-e">X</span><span class="crayon-o">-</span><span class="crayon-e">Forwarded</span><span class="crayon-o">-</span><span class="crayon-e">Proto</span> <span class="crayon-sy">{</span><span class="crayon-v">scheme</span><span class="crayon-sy">}</span></div>
<div id="crayon-5c3cd5537f7c1071249087-11" class="crayon-line"></div>
<div id="crayon-5c3cd5537f7c1071249087-12" class="crayon-line crayon-striped-line"><span class="crayon-sy">}</span></div>
<div id="crayon-5c3cd5537f7c1071249087-13" class="crayon-line"></div>
<div id="crayon-5c3cd5537f7c1071249087-14" class="crayon-line crayon-striped-line"><span class="crayon-v">log</span> <span class="crayon-o">/</span><span class="crayon-v">conf</span><span class="crayon-o">/</span><span class="crayon-v">blog</span><span class="crayon-sy">.</span><span class="crayon-i">log</span></div>
<div id="crayon-5c3cd5537f7c1071249087-15" class="crayon-line"></div>
</div></td>
</tr>
</tbody>
</table>
</div>
</div>
启动docker:
<div id="crayon-5c3cd5537f7c5903837483" class="crayon-syntax crayon-theme-turnwall crayon-font-monospace crayon-os-pc print-yes notranslate" data-settings=" minimize scroll-mouseover">
<div class="crayon-plain-wrap"></div>
<div class="crayon-main">
<table class="crayon-table">
<tbody>
<tr class="crayon-row">
<td class="crayon-nums " data-settings="show">
<div class="crayon-nums-content">
<div class="crayon-num" data-line="crayon-5c3cd5537f7c5903837483-1">1</div>
<div class="crayon-num crayon-striped-num" data-line="crayon-5c3cd5537f7c5903837483-2">2</div>
</div></td>
<td class="crayon-code">
<div class="crayon-pre">
<div id="crayon-5c3cd5537f7c5903837483-1" class="crayon-line"><span class="crayon-e">docker </span><span class="crayon-v">run</span> <span class="crayon-o">-</span><span class="crayon-v">d</span> <span class="crayon-o">--</span><span class="crayon-e">name </span><span class="crayon-v">caddy</span><span class="crayon-o">-</span><span class="crayon-v">blog</span> <span class="crayon-o">-</span><span class="crayon-i">p</span> <span class="crayon-cn">443</span><span class="crayon-o">:</span><span class="crayon-cn">443</span><span class="crayon-o">/</span><span class="crayon-v">udp</span> <span class="crayon-o">-</span><span class="crayon-i">v</span> <span class="crayon-v">YOUR_CERT_KEY_DIR</span><span class="crayon-o">:</span> <span class="crayon-v">YOUR_CERT_KEY_DIR</span> <span class="crayon-o">-</span><span class="crayon-v">v</span><span class="crayon-h">  </span><span class="crayon-o">/</span><span class="crayon-v">conf</span><span class="crayon-o">:</span><span class="crayon-o">/</span><span class="crayon-e">conf </span><span class="crayon-v">liudanking</span><span class="crayon-o">/</span><span class="crayon-v">docker</span><span class="crayon-o">-</span><span class="crayon-e">caddy </span><span class="crayon-v">caddy</span> <span class="crayon-o">-</span><span class="crayon-v">quic</span> <span class="crayon-o">-</span><span class="crayon-v">conf</span> <span class="crayon-o">/</span><span class="crayon-v">conf</span><span class="crayon-o">/</span><span class="crayon-v">blog</span><span class="crayon-sy">.</span><span class="crayon-i">conf</span></div>
<div id="crayon-5c3cd5537f7c5903837483-2" class="crayon-line crayon-striped-line"></div>
</div></td>
</tr>
</tbody>
</table>
</div>
</div>
<h2>开启Chrome浏览器QUIC特性</h2>
在<a href="chrome://flags/">chrome://flags/</a>中找到<code>Experimental QUIC protocol</code>, 设置为<code>Enabled</code>. 重启浏览器生效。
<h2>测试QUIC开启状态</h2>
重新访问本站<a href="https://liudanking.com/">https://liudanking.com</a>, 然后在浏览器中打开：<a href="chrome://net-internals/#quic">chrome://net-internals/#quic</a>。如果你看到了QUIC sessins，则开启成功：

<img src="https://ws1.sinaimg.cn/large/44cd29dagy1fpf0jxgvscj21xu06gdi2.jpg" alt="" />

当然，你也可以给Chrome安装一个<a href="https://chrome.google.com/webstore/detail/mpbpobfflnpcgagjijhmgnchggcjblin">HTTP/2 and SPDY indicator</a>(An indicator button for HTTP/2, SPDY and QUIC support by each website) 更加直观的观察网站对http/2, QUIC的支持情况。
