require File.expand_path(File.dirname(__FILE__) + '/test_helper')

# Test cases for the CssParser.
class CssParserTests < Minitest::Test
  include CssParser

  def setup
    @cp = Parser.new
  end

  def test_at_page_rule
    # from http://www.w3.org/TR/CSS21/page.html#page-selectors
    css = <<-CSS
      @page { margin: 2cm }

      @page :first {
        margin-top: 10cm
      }
    CSS

    @cp.add_block!(css)

    assert_equal 'margin: 2cm;', @cp.find_by_selector('@page').join(' ')
    assert_equal 'margin-top: 10cm;', @cp.find_by_selector('@page :first').join(' ')

    rules = @cp.find_rule_sets(['@page', '@page :first'])

    assert_equal 2, rules.count
    assert_equal (6..27), rules.first.offset
    assert_equal (35..82), rules.last.offset
  end

  def test_should_ignore_comments
    # see http://www.w3.org/Style/CSS/Test/CSS2.1/current/html4/t040109-c17-comments-00-b.htm
    css =<<-CSS
      /* This is a CSS comment. */
      .one {color: green;} /* Another comment */
      /* The following should not be used:
      .one {color: red;} */
      .two {color: green; /* color: yellow; */}
      /**
      .three {color: red;} */
      .three {color: green;}
      /**/
      .four {color: green;}
      /*********/
      .five {color: green;}
      /* a comment **/
      .six {color: green;}
    CSS

    @cp.add_block!(css)
    @cp.each_selector do |sel, decs, spec|
      assert_equal 'color: green;', decs
    end

    # check rule offsets
    i = 0
    offsets = [(41..61), (161..202), (249..271), (289..310), (335..356), (386..406)]
    @cp.each_rule_set do |rule_set, media_types|
      assert_equal offsets[i], rule_set.offset
      i += 1
    end
  end

  def test_parsing_blocks
    # dervived from http://www.w3.org/TR/CSS21/syndata.html#rule-sets
    css = <<-CSS
      div[name='test'] {

      color:

      red;

      }div:hover{coloR:red;
         }div:first-letter{color:red;/*color:blue;}"commented out"*/}

      p[example="public class foo\
      {\
          private string x;\
      \
          foo(int x) {\
              this.x = 'test';\
              this.x = \"test\";\
          }\
      \
      }"] { color: red }

      p { color:red}
    CSS

    @cp.add_block!(css)

    @cp.each_selector do |sel, decs, spec|
      assert_equal 'color: red;', decs
    end

    # check rule offsets
    i = 0
    offsets = [(6..59), (59..90), (90..149), (157..347), (355..369)]
    @cp.each_rule_set do |rule_set, media_types|
      assert_equal offsets[i], rule_set.offset
      i += 1
    end
  end

  def test_ignoring_malformed_declarations
    # dervived from http://www.w3.org/TR/CSS21/syndata.html#parsing-errors
    css = <<-CSS
      p { color:green }
      p { color:green; color }  /* malformed declaration missing ':', value */
      p { color:red;   color; color:green }  /* same with expected recovery */
      p { color:green; color: } /* malformed declaration missing value */
      p { color:red;   color:; color:green } /* same with expected recovery */
      p { color:green; color{;color:maroon} } /* unexpected tokens { } */
      p { color:red;   color{;color:maroon}; color:green } /* same with recovery */
    CSS

    @cp.add_block!(css)

    @cp.each_selector do |sel, decs, spec|
      assert_equal 'color: green;', decs
    end

    # check rule offsets
    i = 0
    offsets = [(6..23), (30..54), (109..146), (188..213), (262..300), (341..380), (415..467)]
    @cp.each_rule_set do |rule_set, media_types|
      assert_equal offsets[i], rule_set.offset
      i += 1
    end
  end

  def test_find_rule_sets
    css = <<-CSS
      h1, h2 { color: blue; }
      h1 { font-size: 10px; }
      h2 { font-size: 5px; }
      article  h3  { color: black; }
      article
      h3 { background-color: white; }
    CSS

    @cp.add_block!(css)
    assert_equal 2, @cp.find_rule_sets(["h2"]).size
    assert_equal 3, @cp.find_rule_sets(["h1", "h2"]).size
    assert_equal 2, @cp.find_rule_sets(["article h3"]).size
    assert_equal 2, @cp.find_rule_sets(["  article \t  \n  h3 \n "]).size
  end

  def test_calculating_specificity
    # from http://www.w3.org/TR/CSS21/cascade.html#specificity
    assert_equal 0,   CssParser.calculate_specificity('*')
    assert_equal 1,   CssParser.calculate_specificity('li')
    assert_equal 2,   CssParser.calculate_specificity('li:first-line')
    assert_equal 2,   CssParser.calculate_specificity('ul li')
    assert_equal 3,   CssParser.calculate_specificity('ul ol+li')
    assert_equal 11,  CssParser.calculate_specificity('h1 + *[rel=up]')
    assert_equal 13,  CssParser.calculate_specificity('ul ol li.red')
    assert_equal 21,  CssParser.calculate_specificity('li.red.level')
    assert_equal 100, CssParser.calculate_specificity('#x34y')

    # from http://www.hixie.ch/tests/adhoc/css/cascade/specificity/003.html
    assert_equal CssParser.calculate_specificity('div *'), CssParser.calculate_specificity('p')
    assert CssParser.calculate_specificity('body div *') > CssParser.calculate_specificity('div *')

    # other tests
    assert_equal 11, CssParser.calculate_specificity('h1[id|=123]')
  end

  def test_converting_uris
    base_uri = 'http://www.example.org/style/basic.css'
    ["body { background: url(yellow) };", "body { background: url('yellow') };",
      "body { background: url('/style/yellow') };",
      "body { background: url(\"../style/yellow\") };",
      "body { background: url(\"lib/../../style/yellow\") };"].each do |css|
      converted_css = CssParser.convert_uris(css, base_uri)
      assert_equal "body { background: url('http://www.example.org/style/yellow') };", converted_css
    end

    converted_css = CssParser.convert_uris("body { background: url(../style/yellow-dot_symbol$.png?abc=123&amp;def=456&ghi=789#1011) };", base_uri)
    assert_equal "body { background: url('http://www.example.org/style/yellow-dot_symbol$.png?abc=123&amp;def=456&ghi=789#1011') };", converted_css

    # taken from error log: 2007-10-23 04:37:41#2399
    converted_css = CssParser.convert_uris('.specs {font-family:Helvetica;font-weight:bold;font-style:italic;color:#008CA8;font-size:1.4em;list-style-image:url("images/bullet.gif");}', 'http://www.example.org/directory/file.html')
    assert_equal ".specs {font-family:Helvetica;font-weight:bold;font-style:italic;color:#008CA8;font-size:1.4em;list-style-image:url('http://www.example.org/directory/images/bullet.gif');}", converted_css
  end

  def test_ruleset_with_braces
=begin
    parser = Parser.new
    parser.add_block!("div { background-color: black !important; }")
    parser.add_block!("div { background-color: red; }")

    rulesets = []

    parser['div'].each do |declaration|
      rulesets << RuleSet.new('div', declaration)
    end

    merged = CssParser.merge(rulesets)

    result: # merged.to_s => "{ background-color: black !important; }"
=end

    new_rule = RuleSet.new('div', "{ background-color: black !important; }")

    assert_equal 'div { background-color: black !important; }', new_rule.to_s
  end
end
