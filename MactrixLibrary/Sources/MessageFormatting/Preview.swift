import SwiftUI

#Preview {
    let sample = """
    <h1>This is a title</h1>

    <h2>This is header 2</h2>
    <h3>This is header 3</h3>
    <h4>This is header 4</h4>
    <h5>This is header 5</h5>
    <h6>This is header 6</h6>

    <p>
    This <em>is</em> <b>bold</b>, <u>underline</u>, <s>strikethrough</s>.
    </p>

    <h2>Rendering lists</h2>

    <p>Here is a list of bullets.</p>

    <ul>
    <li>Item one</li>
    <li>Item two</li>
    <li>Item three</li>
    </ul>

    <p>We can also make ordered lists.</p>

    <ol>
        <li>Item one</li>
        <li>Item two</li>
        <li>Item three</li>
    </ol>

    <h2>Code</h2>

    <p>
    This is how a code block looks like.
    </p>

    <code>
    This is code
    Another line
    </code>

    <hr />

    <p>
    An example of <code>inline</code> code.
    </p>

    <h2>Links</h2>

    This is a link to <a href="https://google.com">google.com</a>
    """

    AttributedTextView(attributedString: parseFormattedBody(sample))
        .frame(height: 600)
}
