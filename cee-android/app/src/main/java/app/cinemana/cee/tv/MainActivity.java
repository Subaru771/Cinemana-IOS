package app.cinemana.cee.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.util.LruCache;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.GridView;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.MediaController;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.VideoView;

import org.json.JSONArray;
import org.json.JSONObject;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** CEE-compatible, Android-TV-first shell. Never assumes a private CEE API. */
public final class MainActivity extends Activity {
    private static final String PRIMARY = "https://cee.buzz/home";
    private static final String MIRROR = "https://cee.buzz.iraq.soft31.com/2";
    private static final int BG = 0xff130609;
    private static final int PANEL = 0xff260f17;
    private static final int RED = 0xfff33342;
    private static final int WHITE = 0xfff7f2f3;

    private final ExecutorService images = Executors.newFixedThreadPool(3);
    private final LruCache<String, Bitmap> artworkCache = new LruCache<>(28);
    private final ArrayList<Poster> posters = new ArrayList<>();
    private final ArrayList<Poster> saved = new ArrayList<>();
    private final ArrayList<Poster> visible = new ArrayList<>();
    private final Set<String> seen = new HashSet<>();
    private WebView web;
    private LinearLayout catalogue;
    private GridView grid;
    private TextView message;
    private TextView heading;
    private FrameLayout body;
    private FrameLayout fullScreen;
    private WebChromeClient.CustomViewCallback fullScreenCallback;
    private SharedPreferences preferences;
    private String tab = "discover";
    private String query = "";
    private boolean mirror = false;
    private boolean arabic = false;

    private static final class Poster {
        String title, link, image;
        Poster(String t, String l, String i) { title=t; link=l; image=i; }
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        preferences = getSharedPreferences("cee-tv", MODE_PRIVATE);
        mirror = preferences.getBoolean("mirror", false);
        String language = preferences.getString("lang", "system");
        arabic = "ar".equals(language) || ("system".equals(language) && getResources().getConfiguration().getLocales().get(0).getLanguage().equals("ar"));
        readSaved();
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        setContentView(root);
        root.addView(makeHeader(), new LinearLayout.LayoutParams(-1, dp(70)));
        body = new FrameLayout(this);
        root.addView(body, new LinearLayout.LayoutParams(-1, 0, 1f));
        makeWebsite();
        makeCatalogue();
        changeTab("discover");
        loadWebsite(mirror ? MIRROR : PRIMARY);
    }

    private String tr(String en, String ar) { return arabic ? ar : en; }
    private int dp(float n) { return (int)(n * getResources().getDisplayMetrics().density + .5f); }
    private GradientDrawable panel(int color, int radius) {
        GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d;
    }
    private Button nav(String title, Runnable call) {
        Button b = new Button(this);
        b.setAllCaps(false);
        b.setText(title);
        b.setTextSize(14);
        b.setTextColor(WHITE);
        b.setBackground(panel(PANEL, 9));
        b.setFocusable(true);
        b.setOnFocusChangeListener((v, focus)->{
            GradientDrawable border = panel(focus ? 0xff5a1827 : PANEL, 9);
            if (focus) border.setStroke(dp(2), RED);
            v.setBackground(border);
        });
        b.setOnClickListener(v -> call.run());
        return b;
    }
    private LinearLayout makeHeader() {
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(20), dp(8), dp(12), dp(8));
        header.setBackgroundColor(0xff1b090e);
        TextView title = new TextView(this);
        title.setText("CINEMANA  |  CEE");
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(WHITE);
        title.setTextSize(22);
        header.addView(title, new LinearLayout.LayoutParams(dp(280), -2));
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        header.addView(scroll, new LinearLayout.LayoutParams(0, -1, 1));
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        scroll.addView(row);
        addTab(row, tr("Discover", "اكتشف"), "discover");
        addTab(row, tr("Saved", "المحفوظات"), "saved");
        addTab(row, tr("Website", "الموقع"), "website");
        addAction(row, tr("Search", "البحث"), this::promptSearch);
        addAction(row, tr("Refresh", "تحديث"), () -> {web.reload(); Toast.makeText(this, tr("Refreshing CEE", "جاري تحديث الموقع"), Toast.LENGTH_SHORT).show();});
        addAction(row, tr("Downloads", "التنزيلات"), this::openDownloads);
        addAction(row, tr("Settings", "الإعدادات"), this::settings);
        return header;
    }
    private void addTab(LinearLayout row, String title, String id) { addAction(row, title, ()->changeTab(id)); }
    private void addAction(LinearLayout row, String title, Runnable call) {
        Button button = nav(title, call);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(48));
        p.setMargins(dp(5), 0, dp(5), 0);
        row.addView(button, p);
    }
    private void makeWebsite() {
        web = new WebView(this);
        web.setBackgroundColor(BG);
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);
        WebSettings cfg = web.getSettings();
        cfg.setJavaScriptEnabled(true);
        cfg.setDomStorageEnabled(true);
        cfg.setMediaPlaybackRequiresUserGesture(false);
        cfg.setSupportMultipleWindows(false);
        cfg.setJavaScriptCanOpenWindowsAutomatically(false);
        cfg.setBuiltInZoomControls(false);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                String scheme = u.getScheme();
                if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) return true;
                if (isVideo(u.toString())) { nativeVideo(u.toString()); return true; }
                return false;
            }
            @Override public void onPageFinished(WebView view, String url) {
                view.evaluateJavascript("(function(){let x=document.createElement('style');x.textContent='*:focus{outline:3px solid #f33342 !important;outline-offset:2px !important}';document.head.appendChild(x)})()", null);
                scanPosters();
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onShowCustomView(View view, CustomViewCallback cb) {
                if (fullScreen != null) { cb.onCustomViewHidden(); return; }
                fullScreenCallback = cb;
                fullScreen = new FrameLayout(MainActivity.this);
                fullScreen.setBackgroundColor(Color.BLACK);
                fullScreen.addView(view, new FrameLayout.LayoutParams(-1, -1));
                addContentView(fullScreen, new ViewGroup.LayoutParams(-1, -1));
                getWindow().getDecorView().setSystemUiVisibility(5894 | View.SYSTEM_UI_FLAG_FULLSCREEN);
            }
            @Override public void onHideCustomView() { exitFullScreen(); }
        });
        web.setDownloadListener((url, ua, disposition, mime, size)-> {
            if (!url.startsWith("https://") && !url.startsWith("http://")) return;
            new AlertDialog.Builder(this).setTitle(tr("Download file?", "تنزيل الملف؟"))
                .setMessage(Uri.parse(url).getLastPathSegment())
                .setPositiveButton(tr("Download", "تنزيل"), (d, w)->download(url, ua, mime))
                .setNegativeButton(tr("Cancel", "إلغاء"), null).show();
        });
        body.addView(web, new FrameLayout.LayoutParams(-1, -1));
    }
    private void makeCatalogue() {
        catalogue = new LinearLayout(this);
        catalogue.setOrientation(LinearLayout.VERTICAL);
        catalogue.setBackgroundColor(BG);
        catalogue.setPadding(dp(20),dp(14),dp(20),dp(12));
        heading = new TextView(this);
        heading.setTextSize(21);
        heading.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        heading.setTextColor(WHITE);
        catalogue.addView(heading, new LinearLayout.LayoutParams(-1, dp(44)));
        grid = new GridView(this);
        grid.setNumColumns(5);
        grid.setVerticalSpacing(dp(16));
        grid.setHorizontalSpacing(dp(13));
        grid.setFocusable(true);
        grid.setClipToPadding(false);
        grid.setOnItemClickListener((parent, view, position, id) -> {
            if (position < visible.size()) { loadWebsite(visible.get(position).link); changeTab("website"); }
        });
        grid.setOnItemLongClickListener((parent, view, position, id) -> {
            if (position < visible.size()) { toggleSaved(visible.get(position)); return true; }
            return false;
        });
        catalogue.addView(grid, new LinearLayout.LayoutParams(-1,0,1f));
        message = new TextView(this);
        message.setTextSize(13);
        message.setTextColor(0xffc0a3aa);
        message.setPadding(dp(6), dp(12),0,0);
        catalogue.addView(message, new LinearLayout.LayoutParams(-1, dp(48)));
        body.addView(catalogue,new FrameLayout.LayoutParams(-1,-1));
    }
    private void changeTab(String newTab) {
        tab = newTab;
        boolean site = "website".equals(tab);
        if (web != null) {
            web.setVisibility(site ? View.VISIBLE : View.INVISIBLE);
            web.setFocusable(site);
        }
        if (catalogue != null) {
            catalogue.setVisibility(site ? View.GONE : View.VISIBLE);
            if (!site) { updateGrid(); grid.requestFocus(); }
        }
        if (site && web != null) web.requestFocus();
    }
    private void updateGrid() {
        if (heading == null) return;
        heading.setText("saved".equals(tab) ? tr("Saved titles", "العناوين المحفوظة") : tr("Discover on CEE", "اكتشف عبر CEE"));
        visible.clear();
        for (Poster item : "saved".equals(tab) ? saved : posters) {
            if (query.isEmpty() || item.title.toLowerCase().contains(query.toLowerCase())) visible.add(item);
        }
        grid.setAdapter(new PosterAdapter());
        message.setText(visible.isEmpty()
             ? tr("No titles found. Open Website to browse CEE. Poster discovery depends on its page structure.",
                  "ماكو عناوين. افتح الموقع لتصفح CEE. عرض الصور يعتمد على تركيب الموقع.")
             : tr("OK = open title · Hold OK = save/remove · Posters loaded: ", "اضغط OK للتشغيل · ضغطة مطولة للحفظ · عدد البوسترات: ") + visible.size());
    }
    private class PosterAdapter extends BaseAdapter {
        @Override public int getCount() { return visible.size(); }
        @Override public Object getItem(int p) { return visible.get(p); }
        @Override public long getItemId(int p) { return p; }
        @Override public View getView(int index, View recycled, ViewGroup parent) {
            Poster poster = visible.get(index);
            LinearLayout card = new LinearLayout(MainActivity.this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(4),dp(4),dp(4),dp(5));
            card.setBackground(panel(PANEL, 9));
            card.setFocusable(true);
            card.setOnFocusChangeListener((v, focused) -> {
                GradientDrawable shape = panel(focused ? 0xff45101d : PANEL, 9);
                if (focused) shape.setStroke(dp(3), RED);
                v.setBackground(shape);
            });
            card.setOnClickListener(v->{ loadWebsite(poster.link); changeTab("website"); });
            card.setOnLongClickListener(v->{ toggleSaved(poster); return true; });
            ImageView art = new ImageView(MainActivity.this);
            art.setScaleType(ImageView.ScaleType.CENTER_CROP);
            art.setBackgroundColor(0xff331620);
            art.setImageResource(android.R.drawable.ic_media_play);
            card.addView(art,new LinearLayout.LayoutParams(-1, dp(172)));
            loadPoster(poster.image, art);
            TextView name = new TextView(MainActivity.this);
            name.setText(poster.title + (isSaved(poster.link) ? "  ★" : ""));
            name.setMaxLines(2);
            name.setTextSize(12);
            name.setTextColor(WHITE);
            name.setPadding(dp(3),dp(6),dp(3),dp(2));
            card.addView(name, new LinearLayout.LayoutParams(-1,dp(43)));
            card.setLayoutParams(new AbsListView.LayoutParams(-1,dp(229)));
            return card;
        }
    }
    private void loadPoster(String url, ImageView target) {
        if (url == null || !url.startsWith("https://")) return;
        Bitmap cached = artworkCache.get(url);
        if (cached != null) { target.setImageBitmap(cached); return; }
        target.setTag(url);
        images.submit(() -> {
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
                c.setConnectTimeout(4500); c.setReadTimeout(6500);
                c.setRequestProperty("User-Agent", "Mozilla/5.0");
                Bitmap bitmap;
                try (InputStream s = c.getInputStream()) { bitmap = BitmapFactory.decodeStream(s); }
                c.disconnect();
                if (bitmap != null) {
                    artworkCache.put(url,bitmap);
                    runOnUiThread(()->{if (url.equals(target.getTag())) target.setImageBitmap(bitmap);});
                }
            } catch (Exception ignored) {}
        });
    }
    private void scanPosters() {
        String js = "(function(){const a=[],s=new Set();for(const l of document.querySelectorAll('a[href]')){if(a.length>=250)break;const i=l.querySelector('img');if(!i)continue;const u=l.href,t=(l.getAttribute('aria-label')||i.alt||l.title||l.innerText||'').trim().slice(0,140),p=i.currentSrc||i.src||i.getAttribute('data-src')||'';if(!/^https?:\\/\\//i.test(u)||!/^https?:\\/\\//i.test(p)||t.length<2||s.has(u))continue;s.add(u);a.push({title:t,link:u,image:p});}return JSON.stringify(a)})()";
        web.evaluateJavascript(js, result -> {
            try {
                String decoded;
                if ("null".equals(result)) return;
                // evaluateJavascript returns a quoted, escaped JSON string
                decoded = new JSONArray("["+result+"]").getString(0);
                JSONArray array = new JSONArray(decoded);
                ArrayList<Poster> fresh = new ArrayList<>();
                Set<String> links = new HashSet<>();
                for (int i=0;i<array.length();i++) {
                    JSONObject o = array.getJSONObject(i);
                    String link=o.optString("link"), image=o.optString("image"), title=o.optString("title");
                    if (!link.startsWith("https://") && !link.startsWith("http://")) continue;
                    if (title.isEmpty()||links.contains(link)) continue;
                    links.add(link); fresh.add(new Poster(title,link,image));
                }
                if (!fresh.isEmpty()) {
                    posters.clear(); posters.addAll(fresh);
                    if ("discover".equals(tab)) updateGrid();
                }
            } catch(Exception ignored) {}
        });
    }
    private void loadWebsite(String url) {
        Uri uri = Uri.parse(url);
        if (!"https".equalsIgnoreCase(uri.getScheme()) && !"http".equalsIgnoreCase(uri.getScheme())) return;
        web.loadUrl(url);
    }
    private void toggleSaved(Poster poster) {
        if (isSaved(poster.link)) saved.removeIf(item -> item.link.equals(poster.link));
        else saved.add(0,poster);
        JSONArray arr = new JSONArray();
        for (Poster p : saved) {JSONObject o=new JSONObject();try {
            o.put("title",p.title);o.put("link",p.link);o.put("image",p.image);
            arr.put(o);
        }catch(Exception ignored){}}
        preferences.edit().putString("saved",arr.toString()).apply();
        updateGrid();
        Toast.makeText(this,tr("Saved list updated","تم تحديث المحفوظات"),Toast.LENGTH_SHORT).show();
    }
    private boolean isSaved(String link) {
        for (Poster p:saved) if(p.link.equals(link))return true;
        return false;
    }
    private void readSaved() {
        try {
            JSONArray a=new JSONArray(preferences.getString("saved","[]"));
            for(int i=0;i<a.length();i++) {JSONObject o=a.getJSONObject(i);
                String link=o.optString("link");
                if(link.startsWith("http://")||link.startsWith("https://"))
                    saved.add(new Poster(o.optString("title"),link,o.optString("image")));
            }
        }catch(Exception ignored){}
    }
    private void promptSearch() {
        EditText search = new EditText(this);
        search.setSingleLine(true); search.setText(query);
        search.setTextColor(Color.BLACK);
        new AlertDialog.Builder(this).setTitle(tr("Filter loaded titles","فلترة العناوين"))
            .setView(search).setPositiveButton(tr("Search","بحث"),(d,w)->{
                query=search.getText().toString().trim(); changeTab("discover");
            }).setNegativeButton(tr("Cancel","إلغاء"),null).show();
    }
    private void settings() {
        String[] menu = {
            tr("Open CEE primary source","المصدر الرئيسي"),
            tr("Open provided mirror","المصدر البديل"),
            tr("Language: English","اللغة: إنكليزي"),
            tr("Language: Arabic","اللغة: عربي"),
            tr("Language: System","اللغة: حسب الجهاز")
        };
        new AlertDialog.Builder(this).setTitle(tr("CEE Settings","إعدادات CEE"))
            .setItems(menu, (d,index)->{
                if(index<2) {
                    mirror=index==1;preferences.edit().putBoolean("mirror",mirror).apply();
                    loadWebsite(mirror?MIRROR:PRIMARY);changeTab("website");
                } else {
                    preferences.edit().putString("lang",index==2?"en":index==3?"ar":"system").apply();
                    Toast.makeText(this,tr("Restart app to update UI language","أعد تشغيل التطبيق لتغيير اللغة"),Toast.LENGTH_SHORT).show();
                }
            }).show();
    }
    private boolean isVideo(String link) {
        String s=Uri.parse(link).getPath();
        if(s==null)return false;
        s=s.toLowerCase();
        return s.endsWith(".mp4") || s.endsWith(".m3u8") || s.endsWith(".m4v");
    }
    private void nativeVideo(String url) {
        FrameLayout overlay = new FrameLayout(this);
        overlay.setBackgroundColor(Color.BLACK);
        VideoView player=new VideoView(this);
        overlay.addView(player,new FrameLayout.LayoutParams(-1,-1));
        addContentView(overlay,new ViewGroup.LayoutParams(-1,-1));
        MediaController controller=new MediaController(this);
        controller.setAnchorView(player);
        player.setMediaController(controller);
        player.setVideoURI(Uri.parse(url));
        player.setOnErrorListener((p,what,extra)->{
            Toast.makeText(this,tr("Direct playback unavailable; try website player","تعذر التشغيل المباشر؛ جرّب مشغل الموقع"),Toast.LENGTH_LONG).show();
            ((ViewGroup)overlay.getParent()).removeView(overlay);
            changeTab("website");
            return true;
        });
        player.setOnCompletionListener(mp->{((ViewGroup)overlay.getParent()).removeView(overlay);});
        overlay.setFocusableInTouchMode(true);
        overlay.requestFocus();
        overlay.setOnKeyListener((v,code,event)->{
            if(code==KeyEvent.KEYCODE_BACK && event.getAction()==KeyEvent.ACTION_UP) {
                player.stopPlayback(); ((ViewGroup)overlay.getParent()).removeView(overlay); return true;
            }return false;
        });
        player.start();
    }
    private void download(String url, String agent, String mime) {
        try {
            DownloadManager.Request request=new DownloadManager.Request(Uri.parse(url));
            request.setTitle("CEE download");
            request.setDescription("Cinemana CEE TV");
            if(agent!=null)request.addRequestHeader("User-Agent",agent);
            String cookie=CookieManager.getInstance().getCookie(url);
            if(cookie!=null)request.addRequestHeader("Cookie",cookie);
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS,
                android.webkit.URLUtil.guessFileName(url,null,mime));
            ((DownloadManager)getSystemService(Context.DOWNLOAD_SERVICE)).enqueue(request);
            Toast.makeText(this,tr("Download started","بدأ التنزيل"),Toast.LENGTH_SHORT).show();
        }catch(Exception e){Toast.makeText(this,e.getMessage(),Toast.LENGTH_LONG).show();}
    }
    private void openDownloads() {
        try {startActivity(new Intent(DownloadManager.ACTION_VIEW_DOWNLOADS));}
        catch(Exception e){Toast.makeText(this,tr("Open Downloads in your TV file manager","افتح التنزيلات من مدير الملفات"),Toast.LENGTH_SHORT).show();}
    }
    private void exitFullScreen() {
        if(fullScreen==null)return;
        if(fullScreen.getParent() instanceof ViewGroup) ((ViewGroup)fullScreen.getParent()).removeView(fullScreen);
        fullScreen=null;
        if(fullScreenCallback!=null)fullScreenCallback.onCustomViewHidden();
        fullScreenCallback=null;
        getWindow().getDecorView().setSystemUiVisibility(0);
    }
    @Override public void onBackPressed() {
        if(fullScreen!=null){exitFullScreen();return;}
        if("website".equals(tab)&&web.canGoBack()){web.goBack();return;}
        if(!"discover".equals(tab)){changeTab("discover");return;}
        super.onBackPressed();
    }
    @Override public void onDestroy() {
        exitFullScreen();
        web.destroy();
        images.shutdownNow();
        super.onDestroy();
    }
}
