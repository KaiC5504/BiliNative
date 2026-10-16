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

    static let viewDetail = #"""
    {"code":0,"message":"0","ttl":1,"data":{"bvid":"BV1GJ411x7h7","aid":80433022,"videos":2,"copyright":1,"pic":"https://i0.hdslb.com/bfs/archive/cover-0001.jpg","title":"测试视频","pubdate":1760000000,"ctime":1760000100,"desc":"视频简介 @测试用户","desc_v2":[{"raw_text":"视频简介 ","type":1,"biz_id":0},{"raw_text":"测试用户","type":2,"biz_id":42}],"duration":312,
    "owner":{"mid":1,"name":"UP主","face":"https://i0.hdslb.com/bfs/face/face-0001.jpg"},
    "stat":{"aid":80433022,"view":123456,"danmaku":321,"reply":456,"favorite":7890,"coin":2345,"share":678,"now_rank":0,"his_rank":0,"like":9131,"dislike":0},
    "dimension":{"width":1080,"height":1920,"rotate":0},
    "honor_reply":{"honor":[{"aid":80433022,"type":4,"desc":"活动","weekly_recommend_num":0}]},
    "staff":[],
    "pages":[{"cid":137649199,"page":1,"from":"vupload","part":"第一集","duration":212},{"cid":137649200,"page":2,"from":"vupload","part":"第二集","duration":100}],
    "ugc_season":{"id":5001,"title":"测试合集","cover":"https://i0.hdslb.com/bfs/archive/season-0001.jpg","mid":1,"intro":"合集简介","sections":[
    {"season_id":5001,"id":6001,"title":"正片","type":1,"episodes":[
    {"season_id":5001,"section_id":6001,"id":80433022,"aid":80433022,"cid":137649199,"title":"第一集","bvid":"BV1GJ411x7h7","arc":{"aid":80433022,"pic":"https://i0.hdslb.com/bfs/archive/ep-0001.jpg","title":"第一集","pubdate":1760000000,"duration":212,"stat":{"aid":80433022,"view":1000,"danmaku":10,"reply":1,"fav":2,"coin":3,"share":4,"like":5}},"page":{"cid":137649199,"page":1,"part":"第一集","duration":212}},
    {"season_id":5001,"section_id":6001,"id":80433100,"aid":80433100,"cid":137649300,"title":"第二集","bvid":"BV1AB411c7mD","arc":{"aid":80433100,"pic":"https://i0.hdslb.com/bfs/archive/ep-0002.jpg","title":"第二集","pubdate":1760000500,"duration":300,"stat":{"aid":80433100,"view":2000,"danmaku":20,"like":6}},"page":{"cid":137649300,"page":1,"part":"第二集","duration":300}}]},
    {"season_id":5001,"id":6002,"title":"特别篇","type":1,"episodes":[
    {"season_id":5001,"section_id":6002,"id":80433200,"aid":80433200,"cid":137649400,"title":"番外","bvid":"BV1CD411d8nE","arc":{"aid":80433200,"pic":"https://i0.hdslb.com/bfs/archive/ep-0003.jpg","title":"番外","pubdate":1760001000,"duration":90,"stat":{"aid":80433200,"view":3000,"danmaku":30,"like":7}},"page":{"cid":137649400,"page":1,"part":"番外","duration":90}}]}]}}}
    """#

    static let playerV2 = #"""
    {"code":0,"message":"0","ttl":1,"data":{"aid":80433022,"bvid":"BV1GJ411x7h7","cid":137649199,"last_play_time":65000,"last_play_cid":137649200,"view_points":[
    {"type":2,"from":0,"to":60,"content":"开场","imgUrl":"","logoUrl":"","team_type":"","team_name":""},
    {"type":2,"from":60,"to":150,"content":"正片","imgUrl":"","logoUrl":"","team_type":"","team_name":""},
    {"type":2,"from":150,"to":212,"content":"结尾","imgUrl":"","logoUrl":"","team_type":"","team_name":""}]}}
    """#

    static let playerV2Highlights = #"""
    {"code":0,"message":"0","ttl":1,"data":{"aid":80433022,"bvid":"BV1GJ411x7h7","cid":137649199,"last_play_time":0,"last_play_cid":0,"view_points":[
    {"type":1,"from":30,"to":45,"content":"高能"}]}}
    """#

    static let related = #"""
    {"code":0,"message":"0","ttl":1,"data":[
    {"aid":90000001,"videos":1,"pic":"https://i0.hdslb.com/bfs/archive/rel-0001.jpg","title":"相关视频一","duration":605,"owner":{"mid":77,"name":"另一个UP","face":"https://i0.hdslb.com/bfs/face/face-0002.jpg"},"stat":{"aid":90000001,"view":50000,"danmaku":120,"reply":9,"favorite":8,"coin":7,"share":6,"like":1500},"cid":137650001,"bvid":"BV1EF411e9oF"},
    {"aid":90000002,"pic":"https://i0.hdslb.com/bfs/archive/rel-0002.jpg","title":"立即下载","duration":0,"owner":{"mid":0,"name":""},"stat":{"view":1,"danmaku":0,"like":0},"cid":0,"bvid":"BV1GH411f0pG","redirect_url":"https://www.bilibili.com/bangumi/play/ep900001"}]}
    """#

    static let online = #"""
    {"code":0,"message":"0","ttl":1,"data":{"total":"1.2万+","count":"1.2万+","show_switch":{"total":true,"count":true},"abtest":{"group":"a"}}}
    """#

    static let playURLResume = #"""
    {"code":0,"message":"0","ttl":1,"data":{"quality":80,"accept_quality":[80,64],"accept_description":["高清 1080P","高清 720P"],"last_play_time":65000,"last_play_cid":137649199,
    "dash":{"duration":214,"video":[{"id":80,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100113.m4s?deadline=1760000000","backupUrl":[],"bandwidth":2000000,"mimeType":"video/mp4","codecs":"avc1.640032","width":1920,"height":1080,"frameRate":"29.412","SegmentBase":{"Initialization":"0-900","indexRange":"901-1500"},"codecid":7}],"audio":[]}}}
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
