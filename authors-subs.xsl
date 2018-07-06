<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="text" />

  <xsl:template name="contributor">
    <xsl:param name="role" />
    <xsl:for-each select="contributor[contains(@role, $role)]">
      <xsl:if test="position() != 1">
        <xsl:text>
</xsl:text>
      </xsl:if>
      <xsl:value-of select="."/>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="creator">
    <xsl:for-each select="creator">
      <xsl:if test="position() != 1">
        <xsl:text>
</xsl:text>
      </xsl:if>
      <xsl:value-of select="."/>
    </xsl:for-each>
  </xsl:template>

<xsl:template match="/amc-authors">

  <xsl:text>s|@/CREATORS/@|</xsl:text>
    <xsl:call-template name="creator"/>
    <xsl:text>|;
</xsl:text>

  <xsl:text>s|@/AUTHORS/@|</xsl:text>
    <xsl:call-template name="contributor">
      <xsl:with-param name="role" select="'author'"/>
    </xsl:call-template>
    <xsl:text>|;
</xsl:text>

  <xsl:text>s|@/TRANSLATORS/@|</xsl:text>
    <xsl:call-template name="contributor">
      <xsl:with-param name="role" select="'translator'"/>
    </xsl:call-template>
    <xsl:text>|;
</xsl:text>

  <xsl:text>s|@/DOCUMENTERS/@|</xsl:text>
    <xsl:call-template name="contributor">
      <xsl:with-param name="role" select="'documenter'"/>
    </xsl:call-template>
    <xsl:text>|;
</xsl:text>

</xsl:template>

</xsl:stylesheet>

