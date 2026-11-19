var ExtensionPreprocessingJS = {
  run: function (args) {
    var selected = String(window.getSelection ? window.getSelection() : '').trim();
    var visible = [];
    if (!selected) {
      var nodes = document.querySelectorAll('h1,h2,h3,p,li,blockquote,pre');
      for (var i = 0; i < nodes.length; i++) {
        var box = nodes[i].getBoundingClientRect();
        var style = window.getComputedStyle(nodes[i]);
        if (box.width > 0 && box.height > 0 && box.bottom > 0 && box.top < window.innerHeight && style.visibility !== 'hidden') {
          var text = (nodes[i].innerText || '').trim();
          if (text) visible.push(text);
        }
      }
    }
    args.completionFunction({
      text: (selected || visible.join('\n\n') || (document.body ? document.body.innerText : '')).slice(0, 12000),
      title: document.title,
      url: document.location.href,
      scope: selected ? 'selection' : 'visible-page'
    });
  }
};
