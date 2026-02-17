import sublime
import sublime_plugin
import textwrap

class WrapYamlCommentCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        for region in self.view.sel():
            if region.empty():
                region = self.view.line(region)
            
            text = self.view.substr(region)
            lines = text.split('\n')
            
            # Detect indentation from first line
            indent = len(lines[0]) - len(lines[0].lstrip())
            indent_str = ' ' * indent
            
            # Unwrap and rejoin
            unwrapped = ' '.join(line.strip() for line in lines if line.strip())
            
            # Rewrap at 80 chars (adjust as needed)
            wrapped = textwrap.fill(unwrapped, width=80, 
                                   initial_indent=indent_str,
                                   subsequent_indent=indent_str)
            
            self.view.replace(edit, region, wrapped)
