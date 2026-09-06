<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:template match="/">
    <html>
      <head><title>WASM Transformed</title></head>
      <body>
        <h1><xsl:value-of select="root/title"/></h1>
        <xsl:for-each select="root/item">
          <div class="item">
            <xsl:value-of select="name"/>
          </div>
        </xsl:for-each>
      </body>
    </html>
  </xsl:template>

</xsl:stylesheet>
