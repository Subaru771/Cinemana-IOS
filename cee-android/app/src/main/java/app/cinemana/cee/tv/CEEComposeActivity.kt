package app.cinemana.cee.tv

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.Intent
import android.os.Bundle
import android.graphics.Color as AndroidColor
import android.webkit.*
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.Toast
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.tv.material3.Border
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import androidx.tv.material3.darkColorScheme
import coil.compose.AsyncImage
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

private val Red = Color(0xFFFF5262)
private val Bg = Color(0xFF0B0E15)
private val Panel = Color(0xFF171D28)
private val Dim = Color(0xFFA9B1C0)
private val Focus = Color(0xFFB64C62)
private data class Card(val index:Int,val title:String,val image:String,val link:String){
    val id:String get()=title+"|"+image
}
class CEEComposeActivity:ComponentActivity(){
    private val cards=mutableStateListOf<Card>()
    private val favorites=mutableStateListOf<Card>()
    private var tab by mutableIntStateOf(0)
    private var selected by mutableStateOf<Card?>(null)
    private var website by mutableStateOf(false)
    private var searchOpen by mutableStateOf(false)
    private var search by mutableStateOf("")
    private var mirror by mutableStateOf(false)
    private var arabic by mutableStateOf(false)
    private var loading by mutableStateOf(true)
    private var websiteError by mutableStateOf("")
    private lateinit var browser:WebView
    private var fullscreen:FrameLayout?=null
    private var fullscreenCallback:WebChromeClient.CustomViewCallback?=null
    private fun tr(en:String,ar:String)=if(arabic)ar else en
    private fun site()=if(mirror)"https://cee.buzz.iraq.soft31.com/2" else "https://cee.buzz/home"

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState)
        window.statusBarColor=AndroidColor.rgb(11,14,21)
        window.navigationBarColor=AndroidColor.rgb(11,14,21)
        val prefs=getSharedPreferences("cee-compose",MODE_PRIVATE)
        mirror=prefs.getBoolean("mirror",false)
        arabic=prefs.getString("lang","system").let {
            it=="ar" || (it=="system" && resources.configuration.locales.get(0).language=="ar")
        }
        try{
            val arr=JSONArray(prefs.getString("saved","[]"))
            for(i in 0 until arr.length()){
                val o=arr.getJSONObject(i)
                favorites.add(Card(o.optInt("i",i),o.optString("t"),o.optString("p"),o.optString("l")))
            }
        }catch(_:Exception){}
        browser=WebView(this).apply {
            setBackgroundColor(AndroidColor.rgb(11,14,21))
            settings.javaScriptEnabled=true
            settings.domStorageEnabled=true
            settings.mediaPlaybackRequiresUserGesture=false
            settings.setSupportMultipleWindows(false)
            webViewClient=object:WebViewClient(){
                override fun onPageFinished(v:WebView?,url:String?){
                    loading=false;websiteError="";scan()
                    postDelayed({scan()},1300)
                }
                override fun onReceivedError(v:WebView?,r:WebResourceRequest?,e:WebResourceError?){
                    if(r?.isForMainFrame==true){loading=false;websiteError=e?.description?.toString()?:"CEE unavailable"}
                }
            }
            webChromeClient=object:WebChromeClient(){
                override fun onShowCustomView(view:View?,callback:CustomViewCallback?){
                    if(view==null || fullscreen!=null){callback?.onCustomViewHidden();return}
                    val frame=FrameLayout(this@CEEComposeActivity).apply{
                        setBackgroundColor(AndroidColor.BLACK)
                        addView(view,FrameLayout.LayoutParams(-1,-1))
                    }
                    fullscreen=frame;fullscreenCallback=callback
                    addContentView(frame,ViewGroup.LayoutParams(-1,-1))
                    window.decorView.systemUiVisibility=5894 or View.SYSTEM_UI_FLAG_FULLSCREEN
                }
                override fun onHideCustomView(){exitFullscreen()}
            }
            setDownloadListener { url,agent,disposition,mime,_ ->
                try{
                    if(!url.startsWith("https://") && !url.startsWith("http://"))return@setDownloadListener
                    val r=DownloadManager.Request(Uri.parse(url))
                    if(agent!=null)r.addRequestHeader("User-Agent",agent)
                    CookieManager.getInstance().getCookie(url)?.let{r.addRequestHeader("Cookie",it)}
                    r.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    r.setDestinationInExternalPublicDir(android.os.Environment.DIRECTORY_DOWNLOADS,
                        URLUtil.guessFileName(url,disposition,mime))
                    (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(r)
                    Toast.makeText(this@CEEComposeActivity,tr("Download started","بدأ التنزيل"),Toast.LENGTH_SHORT).show()
                }catch(_:Exception){
                    Toast.makeText(this@CEEComposeActivity,tr("Download unavailable","التنزيل غير متوفر"),Toast.LENGTH_LONG).show()
                }
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser,true)
        browser.loadUrl(site())
        setContent{
            MaterialTheme(colorScheme=darkColorScheme(primary=Red,background=Bg,surface=Panel,
                onBackground=Color.White,onSurface=Color.White)){
                Root()
            }
        }
    }
    private fun scan(){
        if(!::browser.isInitialized)return
        val js="""(function(){
            const result=[],seen=new Set();
            document.querySelectorAll('[data-cee-native]').forEach(e=>e.removeAttribute('data-cee-native'));
            function add(el,img){
                if(!el || !img || result.length>=160)return;
                const url=img.currentSrc||img.src||img.getAttribute('data-src')||'';
                if(!/^https?:\/\//i.test(url))return;
                const title=(el.getAttribute('aria-label')||el.getAttribute('title')||img.alt||el.innerText||'').replace(/\s+/g,' ').trim().slice(0,120);
                if(title.length<2||seen.has(title.toLowerCase()+'|'+url))return;
                seen.add(title.toLowerCase()+'|'+url);
                let link='';try{link=el.href?new URL(el.href,document.baseURI).href:''}catch(e){}
                const index=result.length;el.setAttribute('data-cee-native',String(index));
                result.push({index,title,image:url,link});
            }
            for(const img of document.querySelectorAll('img')){
                let el=img.closest('a[href],button,[role="button"],[onclick],.poster,.card')||img.parentElement;
                for(let p=img.parentElement,d=0;p&&d<4;p=p.parentElement,d++){
                    if(p.onclick||window.getComputedStyle(p).cursor==='pointer'){el=p;break}
                }
                add(el,img);
            }
            window.__ceeNativeOpen=function(n){const e=document.querySelector('[data-cee-native="'+Number(n)+'"]');if(!e)return false;e.scrollIntoView({block:'center'});e.click();return true};
            return JSON.stringify(result);
        })()"""
        browser.evaluateJavascript(js){response->
            try{
                val raw=JSONTokener(response).nextValue() as? String?:return@evaluateJavascript
                val arr=JSONArray(raw);val found=mutableListOf<Card>()
                for(i in 0 until arr.length()){
                    val obj=arr.getJSONObject(i)
                    val image=obj.optString("image")
                    if(image.startsWith("http") && obj.optString("title").isNotBlank())
                        found.add(Card(obj.optInt("index",i),obj.optString("title"),image,obj.optString("link")))
                }
                if(found.isNotEmpty()){cards.clear();cards.addAll(found)}
            }catch(_:Exception){}
        }
    }
    private fun open(card:Card){
        selected=null;website=true
        if(card.link.startsWith("https://")||card.link.startsWith("http://"))browser.loadUrl(card.link)
        else browser.evaluateJavascript("window.__ceeNativeOpen("+card.index+")",null)
    }
    private fun save(card:Card){
        if(favorites.any{it.id==card.id})favorites.removeAll{it.id==card.id}
        else favorites.add(0,card)
        val arr=JSONArray()
        for(v in favorites.take(100))arr.put(JSONObject().put("i",v.index).put("t",v.title).put("p",v.image).put("l",v.link))
        getSharedPreferences("cee-compose",MODE_PRIVATE).edit().putString("saved",arr.toString()).apply()
    }
    private fun exitFullscreen(){
        fullscreen?.let{(it.parent as? ViewGroup)?.removeView(it)}
        fullscreen=null;fullscreenCallback?.onCustomViewHidden();fullscreenCallback=null
        window.decorView.systemUiVisibility=0
    }
    private fun back(){
        if(fullscreen!=null){exitFullscreen();return}
        if(website){if(browser.canGoBack())browser.goBack()else website=false;return}
        if(selected!=null){selected=null;return}
        if(searchOpen){searchOpen=false;return}
        tab=0
    }
    override fun onBackPressed(){back()}
    override fun onDestroy(){exitFullscreen();if(::browser.isInitialized)browser.destroy();super.onDestroy()}

    @Composable private fun Root(){
        BackHandler{back()}
        Column(Modifier.fillMaxSize().background(Bg)){
            Row(Modifier.fillMaxWidth().background(Bg).padding(horizontal=28.dp,vertical=12.dp),
                verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){
                Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(Panel),
                    contentAlignment=Alignment.Center){Text("▶",color=Red,fontSize=24.sp)}
                Row(verticalAlignment=Alignment.CenterVertically){
                    Text("Cinemana",fontSize=20.sp,fontWeight=FontWeight.Bold)
                    Text("TV",fontSize=20.sp,fontWeight=FontWeight.Bold,color=Color(0xFFF7354B))
                }
                Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                    verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){
                    listOf(0 to "Home",1 to "Series",2 to "Movies",4 to "History",
                        5 to "My List",6 to "Downloads",7 to "Settings").forEach{(n,label)->
                        TabButton(label,tab==n && !website && !searchOpen){
                            tab=n;website=false;selected=null;searchOpen=false
                            if(n==6)startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
                        }
                    }
                }
                TabButton(if(searchOpen)"Close" else "Search",searchOpen){
                    website=false;selected=null;searchOpen=!searchOpen
                }
                TabButton("CEE",website){website=true;selected=null}
            }
            Box(Modifier.fillMaxSize()){
                AndroidView(factory={(browser.parent as? ViewGroup)?.removeView(browser);browser},
                    modifier=Modifier.fillMaxSize())
                if(!website){
                    Box(Modifier.fillMaxSize().background(Bg)){
                        when {
                            selected!=null -> Detail(selected!!)
                            searchOpen -> Search()
                            tab==7 -> Settings()
                            tab==5 -> Watchlist()
                            tab==1 -> Empty(tr("Series","مسلسلات"),
                                tr("CEE doesn't expose verified series categories. Browse through its website.",
                                   "تصنيف المسلسلات غير متوفر من موقع CEE بصورة مؤكدة."))
                            else -> Home()
                        }
                    }
                } else if(websiteError.isNotEmpty()) {
                    Box(Modifier.fillMaxSize().background(Bg),contentAlignment=Alignment.Center){
                        Column(verticalArrangement=Arrangement.spacedBy(14.dp)){
                            Text(tr("CEE is unavailable","CEE غير متوفر"),fontSize=24.sp)
                            Text(websiteError,color=Dim)
                            Action(tr("Try mirror","جرّب الرابط البديل")){mirror=true;browser.loadUrl(site())}
                        }
                    }
                }
            }
        }
    }
    @Composable private fun TabButton(label:String,active:Boolean,click:()->Unit){
        Surface(onClick=click,shape=ClickableSurfaceDefaults.shape(RoundedCornerShape(10.dp)),
            scale=ClickableSurfaceDefaults.scale(focusedScale=1f),
            border=ClickableSurfaceDefaults.border(
                focusedBorder=Border(BorderStroke(1.dp,Focus),shape=RoundedCornerShape(10.dp))),
            colors=ClickableSurfaceDefaults.colors(containerColor=if(active)Panel else Color.Transparent,
                contentColor=if(active)Color.White else Dim,focusedContainerColor=Color(0xFF31354B),
                focusedContentColor=Color.White)){
            Text(label,fontSize=14.sp,fontWeight=if(active)FontWeight.Bold else FontWeight.Medium,
                modifier=Modifier.padding(horizontal=13.dp,vertical=10.dp))
        }
    }
    @Composable private fun Action(label:String,click:()->Unit){
        Button(onClick=click,shape=ButtonDefaults.shape(shape=RoundedCornerShape(16.dp)),
            scale=ButtonDefaults.scale(focusedScale=1f),
            border=ButtonDefaults.border(focusedBorder=Border(BorderStroke(1.5.dp,Focus),shape=RoundedCornerShape(16.dp))),
            colors=ButtonDefaults.colors(containerColor=Panel,contentColor=Color.White,
                focusedContainerColor=Color(0xFF283247),focusedContentColor=Color.White)){
            Text(label,fontSize=15.sp)
        }
    }
    @Composable private fun Poster(card:Card,focus:()->Unit={},click:()->Unit){
        var isFocused by remember{mutableStateOf(false)}
        Column(Modifier.width(112.dp)){
            Surface(onClick=click,modifier=Modifier.fillMaxWidth().aspectRatio(2f/3f)
                .onFocusChanged{isFocused=it.hasFocus;if(isFocused)focus()},
                shape=ClickableSurfaceDefaults.shape(RoundedCornerShape(12.dp)),
                scale=ClickableSurfaceDefaults.scale(focusedScale=1.065f),
                border=ClickableSurfaceDefaults.border(focusedBorder=Border(
                    BorderStroke(1.5.dp,Focus),shape=RoundedCornerShape(12.dp))),
                colors=ClickableSurfaceDefaults.colors(containerColor=Panel,focusedContainerColor=Panel)){
                AsyncImage(model=card.image,contentDescription=card.title,
                    contentScale=ContentScale.Crop,modifier=Modifier.fillMaxSize())
            }
            Text(card.title,fontSize=12.sp,maxLines=1,overflow=TextOverflow.Ellipsis,
                fontWeight=if(isFocused)FontWeight.SemiBold else FontWeight.Normal,
                color=if(isFocused)Color.White else Color(0xFFB4BCCB),
                modifier=Modifier.padding(top=6.dp,start=2.dp))
        }
    }
    @Composable private fun Hero(card:Card){
        Box(Modifier.fillMaxWidth().height(258.dp).background(Bg)){
            AsyncImage(model=card.image,contentDescription=null,contentScale=ContentScale.Crop,
                modifier=Modifier.align(Alignment.CenterEnd).fillMaxWidth(.62f).fillMaxHeight())
            Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(
                .22f to Bg,.61f to Color(0xF00B0E15),1f to Color(0x110B0E15))))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
                .55f to Color.Transparent,1f to Bg)))
            Column(Modifier.align(Alignment.CenterStart).padding(start=48.dp).fillMaxWidth(.49f),
                verticalArrangement=Arrangement.spacedBy(11.dp)){
                Text("FEATURED  /  DISCOVER",color=Red,fontSize=11.sp,fontWeight=FontWeight.Black)
                Text(card.title,fontSize=33.sp,fontWeight=FontWeight.Bold,maxLines=2,
                    lineHeight=38.sp,overflow=TextOverflow.Ellipsis)
                Text("CEE",color=Dim,fontSize=13.sp)
            }
        }
    }
    @Composable private fun PosterRow(title:String,list:List<Card>,focus:(Card)->Unit={}){
        Column {
            Text(title,fontSize=19.sp,fontWeight=FontWeight.Bold,
                modifier=Modifier.padding(start=48.dp,bottom=7.dp))
            LazyRow(contentPadding=PaddingValues(horizontal=48.dp,vertical=5.dp),
                horizontalArrangement=Arrangement.spacedBy(16.dp)){
                items(list,key={it.id}){v->Poster(v,focus={focus(v)},click={selected=v})}
            }
        }
    }
    @Composable private fun Home(){
        if(cards.isEmpty()){
            Empty(if(loading)tr("Finding movies and series…","جاري تحميل المحتوى")
                  else tr("No titles found","ماكو عناوين"),
                tr("CEE content is loaded from the live website. Open CEE if it doesn't expose poster links.",
                   "المحتوى يعتمد على موقع CEE. افتح الموقع إذا ما ظهرت الصور."))
            return
        }
        var focused by remember{mutableStateOf<Card?>(null)}
        Column(Modifier.fillMaxSize()){
            Hero(focused?:cards.first())
            LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(bottom=40.dp),
                verticalArrangement=Arrangement.spacedBy(19.dp)){
                item{PosterRow(tr("Trending Movies & Series","الرائج من الأفلام والمسلسلات"),
                    cards.take(35),focus={focused=it})}
                if(cards.size>35)item{PosterRow(tr("More on CEE","المزيد من CEE"),
                    cards.drop(35).take(35),focus={focused=it})}
                if(favorites.isNotEmpty())item{PosterRow(tr("My List","قائمتي"),
                    favorites.toList(),focus={focused=it})}
            }
        }
    }
    @Composable private fun Detail(card:Card){
        Column {
            Hero(card)
            Column(Modifier.padding(horizontal=48.dp,vertical=20.dp),
                verticalArrangement=Arrangement.spacedBy(16.dp)){
                Text(card.title,fontSize=28.sp,fontWeight=FontWeight.Bold)
                Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){
                    Action(tr("▶ Play on CEE","▶ تشغيل عبر CEE")){open(card)}
                    Action(if(favorites.any{it.id==card.id})tr("★ Remove from My List","★ إزالة من قائمتي")
                        else tr("☆ Add to My List","☆ أضف لقائمتي")){save(card)}
                    Action(tr("Back","رجوع")){selected=null}
                }
                Text(tr("CEE controls stream playback, episode selection and subtitles.",
                    "مشغل CEE يتحكم بالتشغيل والحلقات والترجمة."),color=Dim,fontSize=13.sp)
            }
        }
    }
    @Composable private fun Search(){
        Column(Modifier.padding(horizontal=48.dp,vertical=20.dp),
            verticalArrangement=Arrangement.spacedBy(14.dp)){
            Text(tr("Search movies and series","بحث الأفلام والمسلسلات"),fontSize=24.sp)
            BasicTextField(value=search,onValueChange={search=it.take(100)},singleLine=true,
                textStyle=TextStyle(color=Color.White,fontSize=20.sp),cursorBrush=SolidColor(Red),
                modifier=Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Panel).padding(14.dp))
            Text(tr("Searches titles discovered on the loaded CEE page.",
                "بحث ضمن العناوين المكتشفة من صفحة CEE."),color=Dim,fontSize=13.sp)
            PosterRow(tr("Results","النتائج"),cards.filter{it.title.contains(search,ignoreCase=true)}.take(50))
        }
    }
    @Composable private fun Watchlist(){
        Column(Modifier.fillMaxSize().padding(top=30.dp)){
            Text(tr("My List","قائمتي"),fontSize=25.sp,modifier=Modifier.padding(start=48.dp))
            Spacer(Modifier.height(18.dp))
            if(favorites.isEmpty())Text(tr("No saved titles","ماكو عناوين محفوظة"),
                color=Dim,modifier=Modifier.padding(start=48.dp))
            else PosterRow(tr("Saved titles","العناوين المحفوظة"),favorites)
        }
    }
    @Composable private fun Empty(title:String,details:String){
        Column(Modifier.fillMaxSize().padding(horizontal=48.dp,vertical=32.dp),
            verticalArrangement=Arrangement.spacedBy(18.dp)){
            Text("DISCOVER",color=Red,fontSize=12.sp,fontWeight=FontWeight.Bold)
            Text(title,fontSize=23.sp,fontWeight=FontWeight.SemiBold)
            Text(details,color=Dim,fontSize=15.sp)
            Action(tr("Open CEE website","افتح موقع CEE")){website=true}
            Action(tr("Retry","إعادة المحاولة")){browser.reload()}
        }
    }
    @Composable private fun Settings(){
        Column(Modifier.fillMaxSize().padding(horizontal=48.dp,vertical=26.dp),
            verticalArrangement=Arrangement.spacedBy(15.dp)){
            Text(tr("Settings","الإعدادات"),fontSize=28.sp,fontWeight=FontWeight.Bold)
            Text(tr("CEE source","مصدر CEE"),color=Red,fontSize=17.sp,fontWeight=FontWeight.Bold)
            Action(if(mirror)tr("Source: mirror","المصدر: البديل")
                   else tr("Source: CEE direct","المصدر: CEE المباشر")){
                mirror=!mirror
                getSharedPreferences("cee-compose",MODE_PRIVATE).edit().putBoolean("mirror",mirror).apply()
                browser.loadUrl(site())
            }
            Action(tr("Reload content","تحديث المحتوى")){browser.reload()}
            Action(tr("Open website","افتح الموقع")){website=true}
            Action(tr("Switch language","تغيير اللغة")){
                arabic=!arabic
                getSharedPreferences("cee-compose",MODE_PRIVATE).edit().putString("lang",if(arabic)"ar" else "en").apply()
            }
            Text(tr("Original CinemanaTV navigation, hero layout and poster-card styles. CEE's site controls the catalog and playback.",
                "تنقل سينمانا وتنسيق الواجهة والبوسترات الأصلي. المحتوى والتشغيل من موقع CEE."),
                color=Dim,fontSize=13.sp)
        }
    }
}