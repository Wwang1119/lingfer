package com.wang.lingfer.screen;

import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.SuperscriptSpan;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Offline public fixture; only packaged in the test APK. */
public final class ReadingFixtureActivity extends Activity {
    private LinearLayout body;
    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density); }
    private void label(CharSequence value, float size, int gap) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(Color.rgb(39,45,45));
        view.setTypeface(Typeface.create("serif",Typeface.NORMAL)); view.setIncludeFontPadding(false);
        view.setLineSpacing(dp(8),1.35f);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1,-2);
        params.bottomMargin=dp(gap); body.addView(view,params);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().setNavigationBarColor(Color.rgb(251,250,246));
        body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(30),dp(42),dp(30),dp(80));body.setBackgroundColor(Color.rgb(251,250,246));
        label("READING STUDY · 01",12,20); label("A clearer view",34,28);
        label("Researchers maintain that consistent practice is more effective than occasional effort.",22,22);
        label("A familiar context can reveal a subtle distinction and make an unfamiliar expression easier to remember.",22,22);
        SpannableString raised = new SpannableString("A reliable method can improve your understanding. Consider the essential argument before reaching a conclusion.");
        raised.setSpan(new SuperscriptSpan(),2,4,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);label(raised,22,22);
        label("Learning becomes meaningful when every detail has a clear purpose. An innovative approach does not necessarily require complicated technology.",22,22);
        label("Public sample · no personal content",13,22);
        TextView reflow=new TextView(this);reflow.setText("Reflow sample");reflow.setTextSize(14);reflow.setTextColor(Color.rgb(54,95,112));reflow.setPadding(0,dp(12),0,dp(12));
        reflow.setOnClickListener(new android.view.View.OnClickListener() {
            boolean shifted=false;
            @Override public void onClick(android.view.View view) {shifted=!shifted;body.setPadding(dp(30),dp(shifted ? 66 : 42),dp(30),dp(80));}
        });body.addView(reflow);
        ScrollView scroll=new ScrollView(this);scroll.addView(body);setContentView(scroll);
    }
}
