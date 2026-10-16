enum Fixtures {
    static let navLoggedOut = #"""
    {"code":-101,"message":"账号未登录","ttl":1,"data":{"isLogin":false,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}
    """#

    static let navLoggedIn = #"""
    {"code":0,"message":"0","ttl":1,"data":{"isLogin":true,"mid":12345,"uname":"测试用户","vipStatus":1,"vipType":2,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}
    """#

    static let view = #"""
    {"code":0,"message":"0","ttl":1,"data":{"bvid":"BV1GJ411x7h7","aid":80433022,"title":"测试视频","owner":{"mid":1,"name":"UP主"},"pages":[{"cid":137649199,"page":1,"part":"第一集","duration":212},{"cid":137649200,"page":2,"part":"第二集","duration":100}]}}
    """#

    static let spi = #"""
    {"code":0,"message":"ok","data":{"b_3":"B3-VALUE-infoc","b_4":"B4-VALUE"}}
    """#

    static let notFound = #"""
    {"code":-404,"message":"啥都木有","ttl":1}
    """#

    static let playURL = #"""
    {"code":0,"message":"0","ttl":1,"data":{"quality":120,"format":"hdflv2","accept_quality":[127,126,125,120,116,80,64,32,16],"accept_description":["超高清 8K","杜比视界","真彩 HDR","超清 4K","高清 1080P60","高清 1080P","高清 720P","清晰 480P","流畅 360P"],
    "dash":{"duration":214,"minBufferTime":1.5,
    "video":[
    {"id":120,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv","base_url":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv","backupUrl":["https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=alibv"],"backup_url":["https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=alibv"],"bandwidth":12000000,"mimeType":"video/mp4","mime_type":"video/mp4","codecs":"hev1.1.6.L153.90","width":3840,"height":2160,"frameRate":"29.412","frame_rate":"29.412","SegmentBase":{"Initialization":"0-1104","indexRange":"1105-1688"},"segment_base":{"initialization":"0-1104","index_range":"1105-1688"},"codecid":12},
    {"id":120,"base_url":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100048.m4s?deadline=1760000000","backup_url":null,"bandwidth":15000000,"mime_type":"video/mp4","codecs":"avc1.640034","width":3840,"height":2160,"segment_base":{"initialization":"0-1000","index_range":"1001-1600"},"codecid":7},
    {"id":80,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100113.m4s?deadline=1760000000","backupUrl":[],"bandwidth":2000000,"mimeType":"video/mp4","codecs":"av01.0.08M.08.0.110.01.01.01.0","width":1920,"height":1080,"frameRate":"29.412","SegmentBase":{"Initialization":"0-900","indexRange":"901-1500"},"codecid":13},
    {"id":126,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100126.m4s?deadline=1760000000","backupUrl":null,"bandwidth":20000000,"mimeType":"video/mp4","codecs":"dvh1.08.07","width":3840,"height":2160,"frameRate":"29.412","SegmentBase":{"Initialization":"0-1200","indexRange":"1201-1800"},"codecid":12}
    ],
    "audio":[
    {"id":30216,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-30216.m4s?deadline=1760000000","backupUrl":null,"bandwidth":67000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","width":0,"height":0,"frameRate":"","SegmentBase":{"Initialization":"0-907","indexRange":"908-1491"},"codecid":0},
    {"id":30280,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-30280.m4s?deadline=1760000000","backupUrl":null,"bandwidth":320000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","width":0,"height":0,"frameRate":"","SegmentBase":{"Initialization":"0-907","indexRange":"908-1491"},"codecid":0}
    ],
    "dolby":{"type":0,"audio":null},"flac":null}}}
    """#

    static let durlOnly = #"""
    {"code":0,"message":"0","ttl":1,"data":{"quality":64,"accept_quality":[64,32],"accept_description":["高清 720P","清晰 480P"],"durl":[{"order":1,"length":120000,"size":1000,"url":"https://upos-sz-mirrorcos.bilivideo.com/a.flv"}]}}
    """#
}
