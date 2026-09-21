<?xml version="1.0" encoding="UTF-8"?>
<!-- SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0 -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="text" encoding="UTF-8"/>

  <xsl:template match="/">
    <xsl:text>\documentclass[11pt,a4paper]{article}
\usepackage[margin=2.5cm]{geometry}
\usepackage{tikz}
\usepackage{tabularx}
\usepackage{listings}
\usepackage[T1]{fontenc}
\usepackage{lmodern}

\lstset{
  language=Swift,
  basicstyle=\ttfamily\small,
  breaklines=true,
  frame=single,
  xleftmargin=1em,
  framexleftmargin=0.5em
}

\title{</xsl:text>
    <xsl:call-template name="escape-latex">
      <xsl:with-param name="text" select="/canvas/@name"/>
    </xsl:call-template>
    <xsl:text>}
\author{</xsl:text>
    <xsl:call-template name="escape-latex">
      <xsl:with-param name="text" select="/canvas/metadata/author"/>
    </xsl:call-template>
    <xsl:text>}
\date{</xsl:text>
    <xsl:value-of select="/canvas/metadata/date"/>
    <xsl:text>}

\begin{document}
\maketitle

</xsl:text>

    <!-- Description -->
    <xsl:if test="/canvas/metadata/description">
      <xsl:call-template name="escape-latex">
        <xsl:with-param name="text" select="/canvas/metadata/description"/>
      </xsl:call-template>
      <xsl:text>

</xsl:text>
    </xsl:if>

    <!-- Architecture section -->
    <xsl:if test="/canvas/architecture">
      <xsl:text>\section{Architecture}

</xsl:text>
      <xsl:for-each select="/canvas/architecture">
        <xsl:text>\begin{itemize}
</xsl:text>
        <xsl:apply-templates select="layer" mode="tree"/>
        <xsl:text>\end{itemize}

</xsl:text>
      </xsl:for-each>
    </xsl:if>

    <!-- Components section -->
    <xsl:if test="/canvas/component">
      <xsl:text>\section{Components}

</xsl:text>
      <xsl:for-each select="/canvas/component">
        <xsl:text>\subsection{</xsl:text>
        <xsl:call-template name="escape-latex">
          <xsl:with-param name="text" select="@name"/>
        </xsl:call-template>
        <xsl:text>}

\begin{tabularx}{\textwidth}{lX}
\hline
</xsl:text>
        <xsl:for-each select="property">
          <xsl:text>\textbf{</xsl:text>
          <xsl:call-template name="escape-latex">
            <xsl:with-param name="text" select="@key"/>
          </xsl:call-template>
          <xsl:text>} &amp; </xsl:text>
          <xsl:call-template name="escape-latex">
            <xsl:with-param name="text" select="."/>
          </xsl:call-template>
          <xsl:text> \\
</xsl:text>
        </xsl:for-each>
        <xsl:text>\hline
\end{tabularx}

</xsl:text>
      </xsl:for-each>
    </xsl:if>

    <!-- Swift stubs section -->
    <xsl:if test="/canvas/swift-stub">
      <xsl:text>\section{Swift Stubs}

</xsl:text>
      <xsl:for-each select="/canvas/swift-stub">
        <xsl:text>\subsection{</xsl:text>
        <xsl:call-template name="escape-latex">
          <xsl:with-param name="text" select="@target"/>
        </xsl:call-template>
        <xsl:text>}

\begin{lstlisting}
</xsl:text>
        <!-- Signature line -->
        <xsl:if test="signature">
          <xsl:value-of select="signature/@access"/>
          <xsl:text> func </xsl:text>
          <xsl:value-of select="signature/@name"/>
          <xsl:text>(</xsl:text>
          <xsl:for-each select="signature/param">
            <xsl:if test="position() &gt; 1">, </xsl:if>
            <xsl:value-of select="@name"/>
            <xsl:text>: </xsl:text>
            <xsl:value-of select="@type"/>
          </xsl:for-each>
          <xsl:text>)</xsl:text>
          <xsl:if test="signature/@async = 'true'"> async</xsl:if>
          <xsl:if test="signature/@throws = 'true'"> throws</xsl:if>
          <xsl:if test="signature/@returns and signature/@returns != 'Void'">
            <xsl:text> -> </xsl:text>
            <xsl:value-of select="signature/@returns"/>
          </xsl:if>
          <xsl:text> {
</xsl:text>
        </xsl:if>
        <!-- Holes -->
        <xsl:for-each select="hole">
          <xsl:text>    // HOLE[</xsl:text>
          <xsl:value-of select="@id"/>
          <xsl:text>]: </xsl:text>
          <xsl:value-of select="@description"/>
          <xsl:text>
    // Type: </xsl:text>
          <xsl:value-of select="@type"/>
          <xsl:text>
    // Expected: </xsl:text>
          <xsl:value-of select="expected"/>
          <xsl:text>
    </xsl:text>
          <xsl:value-of select="placeholder"/>
          <xsl:text>
</xsl:text>
        </xsl:for-each>
        <xsl:if test="signature">
          <xsl:text>}
</xsl:text>
        </xsl:if>
        <xsl:text>\end{lstlisting}

</xsl:text>
      </xsl:for-each>
    </xsl:if>

    <!-- Assembly stubs section -->
    <xsl:if test="/canvas/assembly-stub">
      <xsl:text>\section{Assembly Stubs}

</xsl:text>
      <xsl:for-each select="/canvas/assembly-stub">
        <xsl:text>\subsection{</xsl:text>
        <xsl:call-template name="escape-latex">
          <xsl:with-param name="text" select="@symbol"/>
        </xsl:call-template>
        <xsl:text> (</xsl:text>
        <xsl:value-of select="@abi"/>
        <xsl:text>)}

\begin{lstlisting}
</xsl:text>
        <xsl:for-each select="hole">
          <xsl:text>// HOLE[</xsl:text>
          <xsl:value-of select="@id"/>
          <xsl:text>]: </xsl:text>
          <xsl:value-of select="@description"/>
          <xsl:text>
// Type: </xsl:text>
          <xsl:value-of select="@type"/>
          <xsl:text>
// Expected: </xsl:text>
          <xsl:value-of select="expected"/>
          <xsl:text>
</xsl:text>
        </xsl:for-each>
        <xsl:text>\end{lstlisting}

</xsl:text>
      </xsl:for-each>
    </xsl:if>

    <xsl:text>\end{document}
</xsl:text>
  </xsl:template>

  <!-- Recursive layer template for architecture tree -->
  <xsl:template match="layer" mode="tree">
    <xsl:text>  \item </xsl:text>
    <xsl:call-template name="escape-latex">
      <xsl:with-param name="text" select="@name"/>
    </xsl:call-template>
    <xsl:text>
</xsl:text>
    <xsl:if test="layer">
      <xsl:text>  \begin{itemize}
</xsl:text>
      <xsl:apply-templates select="layer" mode="tree"/>
      <xsl:text>  \end{itemize}
</xsl:text>
    </xsl:if>
  </xsl:template>

  <!-- Minimal LaTeX escaping for & and _ -->
  <xsl:template name="escape-latex">
    <xsl:param name="text"/>
    <xsl:call-template name="string-replace">
      <xsl:with-param name="string">
        <xsl:call-template name="string-replace">
          <xsl:with-param name="string" select="$text"/>
          <xsl:with-param name="search" select="'&amp;'"/>
          <xsl:with-param name="replace" select="'\&amp;'"/>
        </xsl:call-template>
      </xsl:with-param>
      <xsl:with-param name="search" select="'_'"/>
      <xsl:with-param name="replace" select="'\_'"/>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="string-replace">
    <xsl:param name="string"/>
    <xsl:param name="search"/>
    <xsl:param name="replace"/>
    <xsl:choose>
      <xsl:when test="contains($string, $search)">
        <xsl:value-of select="substring-before($string, $search)"/>
        <xsl:value-of select="$replace"/>
        <xsl:call-template name="string-replace">
          <xsl:with-param name="string" select="substring-after($string, $search)"/>
          <xsl:with-param name="search" select="$search"/>
          <xsl:with-param name="replace" select="$replace"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$string"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>
