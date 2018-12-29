/*

 Copyright (C) 2013-2017 Alexis Bienvenue <paamc@passoire.fr>

 This file is part of Auto-Multiple-Choice

 Auto-Multiple-Choice is free software: you can redistribute it
 and/or modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation, either version 2 of
 the License, or (at your option) any later version.

 Auto-Multiple-Choice is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied warranty
 of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Auto-Multiple-Choice.  If not, see
 <http://www.gnu.org/licenses/>.

*/

#ifndef __BUILDPDF__

#define __BUILDPDF__ 1

#include <math.h>
#include <stdio.h>
#include <string.h>
#include <cairo.h>
#include <cairo-pdf.h>
#include <poppler.h>
#include <pango/pangocairo.h>

#include <string>

#ifdef DEBUG
#include <fstream>
#include <iostream>
#endif

#include "opencv2/core/core.hpp"

#if CV_MAJOR_VERSION > 2
  #define OPENCV_23 1
  #define OPENCV_21 1
  #define OPENCV_20 1
  #define OPENCV_30 1
#else
  #if CV_MAJOR_VERSION == 2
    #define OPENCV_20 1
    #if CV_MINOR_VERSION >= 1
       #define OPENCV_21 1
    #endif
    #if CV_MINOR_VERSION >= 3
       #define OPENCV_23 1
    #endif
  #endif
#endif

#include "opencv2/imgproc/imgproc.hpp"
#ifdef OPENCV_30
  #include "opencv2/imgcodecs/imgcodecs.hpp"
#else
  #include "opencv2/highgui/highgui.hpp"
#endif

#define FORMAT_JPEG 1
#define FORMAT_PNG 2

/*

  Helpers to read PNG files from memory (as an array or as a vector)
  with Cairo

 */

struct buffer_closure {
  uchar *buffer;
  unsigned long int length;
  unsigned long int offset;
};

#define BUFFER_CLOSURE(ptr) ((buffer_closure*) (ptr))

static cairo_status_t read_buffer(void *closure, uchar *data, unsigned int length) {
  if(BUFFER_CLOSURE(closure)->offset + length > BUFFER_CLOSURE(closure)->length) {
    return(CAIRO_STATUS_READ_ERROR);
  }
  memcpy(data,BUFFER_CLOSURE(closure)->buffer + BUFFER_CLOSURE(closure)->offset,length);
  BUFFER_CLOSURE(closure)->offset += length;
  return(CAIRO_STATUS_SUCCESS);
}

struct vector_closure {
  std::vector<uchar>::iterator iterator;
  unsigned long int length;
};

#define VECTOR_CLOSURE(ptr) ((vector_closure*) (ptr))

static cairo_status_t read_vector(void *closure, uchar *data, unsigned int length) {
  if(VECTOR_CLOSURE(closure)->length < length) {
    return(CAIRO_STATUS_READ_ERROR);
  }
  std::copy(VECTOR_CLOSURE(closure)->iterator, VECTOR_CLOSURE(closure)->iterator+length,
	    (uchar*)data);
  VECTOR_CLOSURE(closure)->iterator += length;
  VECTOR_CLOSURE(closure)->length -= length;
  return(CAIRO_STATUS_SUCCESS);
}

/*

  BuildPdf

  This class is used by AMC-annotate to build a pdf from image files
  (scans), PDF files (subject pages), with transformation matrix
  support and drawing support (rectangles, circles, marks, text).

*/

/* COORDINATE SYSTEMS:
   
   All coordinate systems has top-left (0,0).

   - LAYOUT/SUBJECT coordinates are pixel-based coordinates of an
     image with density given with dpi, that corresponds to a question
     page. So (0,0) is the top-left corner of the page, and the
     bottom-right corner of the page is (,).

   - SCAN coordinates are pixel-based coordinates on the scan image.

   - PDF coordinates are point(=1/72 inch)-based coordinates of the
     PDF page.
   
   Note that when drawing, all coordinates will be given to BuildPdf
   in pixels (with (0,0) = top-left corner), usually in LAYOUT
   coordinates, but possibly also in PDF coordinates. These
   coordinates will be mapped to PDF coordinates using a
   transformation matrix.
 */

class BuildPdf {
public:
  /* constructor: w and h are the page size in pixels (in the layout
     coordinate system), and d the "dots per point", that is the
     number of pixels in one pt (1pt is 1/72 inches).

  */

  BuildPdf(double w, double h, double d):
    width_in_pixels(w), height_in_pixels(h), dppt(d), n_pages(-1),
    user_one_point(0), margin(0),
    document(NULL), layout(NULL), surface(NULL), cr(NULL),
    image_cr(NULL), image_surface(NULL), fake_image_buffer(NULL),
    font_description(NULL),
    line_width(1.0), font("Linux Libertine O 12"), debug(0),
    scan_expansion(1.0), scan_resize_factor(1.0),
    embedded_image_format(FORMAT_JPEG),
    image_buffer(), scan_max_width(0), scan_max_height(0),
    png_compression_level(9), jpeg_quality(75) { 
    printf(": w_pix=%g h_pix=%g dppt=%g\n",
	   width_in_pixels, height_in_pixels, dppt);
  };

  ~BuildPdf();

  /* call set_debug(1) to get more debugging output on stderr. */
  void set_debug(int d) { debug = d; }


  /* **************************************************************** */
  /* METHODS TO INSERT SCANS (AS BACKGROUND)                          */
  /* **************************************************************** */

  /* the set_* functions can be used to set some parameters' values:

     - embedded_image_format is the format scans will be converted to
       before including them to the PDF file. There are currently two
       choices: FORMAT_PNG or FORMAT_JPEG.

     - jpeg_quality is the JPEG quality (between 0 and 100) used in
       FORMAT_JPEG mode. A small value will lead to small PDF size,
       but with small image quality...

     - png_compression is the PNG compression level (from 1 to 9). Use
       default value 9 for small PDF size (with images longer to
       encode/decode).

     - scan_max_height and scan_max_width define a maximum size for
       the scans: scans which are larger will be resized so that their
       dimensions don't exceed these values. This can allow to get
       smaller PDF files.

     - margin is the margin size in points, used for the global
       verdict text and the questions scores.

  */

  void set_embedded_image_format(int format) { embedded_image_format = format; }
  void set_embedded_png() { embedded_image_format = FORMAT_PNG; }
  void set_embedded_jpeg() { embedded_image_format = FORMAT_JPEG; }
  void set_jpeg_quality(int quality) { jpeg_quality = quality; }
  void set_png_compression_level(int l) { png_compression_level = l; }
  void set_scan_max_height(int mh) { scan_max_height = mh; }
  void set_scan_max_width(int mw) { scan_max_width = mw; }
  void set_margin(double m) { margin = m; }

  /* start_output starts to build a PDF into file
     output_filename. Call it once for each PDF to create, before
     addind images or drawing on it  */

  int start_output(char* output_filename);

  /* close_output finishes with building the PDF, and closes the
     file. */

  void close_output();

  /* next_page begins with another blank page. */

  int next_page();

  /* new_page_from_png begins with another page, with the PNG image as
     a background. The PNG image can be given with its filename, as a
     memoty buffer (pointer and lenght), or as a std::vector memory
     buffer.

     next_page() is called first, unless skip_show_page is set.
  */

  int new_page_from_png(const char* filename);
  int new_page_from_png(void *buffer, unsigned long int buffer_length);
  int new_page_from_png(std::vector<uchar> &buf, int skip_show_page = 0);

  /* resize_scan resizes the cv::Mat image so that its dimensions does
     not exceed scan_max_height and scan_max_width. The scaling factor
     is saved for later use (we need to know it to get the right
     scaling factor between PDF coordinates and scan coordinates) */

  void resize_scan(cv::Mat &image);

  /* new_page_from_image begins with another page, with the image as a
     background.

     The first version will first converted to PNG or JPEG (depending
     on embedded_image_format) using OpenCV.

     With the two latter versions, the image is given as a memory
     buffer, and is attached to the PDF file using the specified
     mime_type (which can be either image/png or image/jpeg).

  */

  int new_page_from_image(const char* filename);
  int new_page_from_image(std::vector<uchar> &image_data, const char* mime_type,
			  int width, int height);
  int new_page_from_image(unsigned char *data, unsigned int size,
			  const char* mime_type,
			  int width, int height);

  /* load_pdf loads a PDF file, to be used later by
     new_page_from_pdf. */

  int load_pdf(char* filename);

  /* new_page_from_pdf begins with another page, using page page_nb of
     the loaded PDF as a background. */

  int new_page_from_pdf(int page_nb);

  /* **************************************************************** */
  /* METHODS TO DRAW ON THE PAGE                                      */
  /* **************************************************************** */

  /* set_line_width sets the line width (in points) for next
     drawings. */

  void set_line_width(double lw);

  /* set_font sets the font for next drawings.
     It then calls validate_font, which updates the font
     description with this new font. */

  int set_font(const char* font);
  int validate_font();
  
  /* color sets the color for next drawings, either with RBG or
     RGBA. Color values must be between 0.0 and 1.0. */

  void color(double r,double g, double b, double a) {
    cairo_set_source_rgba(cr, r, g, b, a);
  }
  void color(double r,double g, double b) {
    cairo_set_source_rgb(cr, r, g, b);
  }

  /* set_matrix_to_scan sets the matrix that transforms layout (subject)
     coordinates to scan coordinates (as recorded in the layout AMC
     database). */

  void set_matrix_to_scan(double a, double b, double c ,double d, double e, double f);

  /* identity_matrix sets the matrix to identity. It can be used when
     the background is the question page, not a scan, or when the
     following drawings will be done with subject/layout coordinates.
  */

  void identity_matrix();

  /* keep_on_scan moves the (x,y) point (in layout/subject
     coordinates) so that the corresponding point stays on the scan */

  void keep_on_scan(double *x, double *y);

  /* drawing symbols (the rectangle on which the symbol should be
     based is given): */

  void draw_rectangle(double xmin, double xmax, double ymin, double ymax);
  void fill_rectangle(double xmin, double xmax, double ymin, double ymax);
  void draw_mark(double xmin, double xmax, double ymin, double ymax);
  void draw_circle(double xmin, double xmax, double ymin, double ymax);

  /* draw_text draws the UTF8 string at (x,y), with x-anchor and
     y-anchor given by xpos and ypos. When xpos=0.0, the text is
     written at the right of (x,y). When xpos=1.0, the text is written
     at the left of (x,y). When 0.5 for exemple, the text is
     x-centered at (x,y). The same applies for ypos in the
     y-direction. */

  void draw_text(double x, double y,
		 double xpos, double ypos, const char *text);

  /* draw_text_margin writes a text in the margin (left margin if
     xside=0, and right margin if xside=1). The point used is a point
     at the border of the margin, so that xpos=0.0 should be used for
     left margin, and xpos=1.0 for tight margin.
  */

  void draw_text_margin(int xside, double y,
			double xpos, double ypos, const char *text);

  /* draw_text_rectangle writes a text in the given rectangle (the
     text is scaled down if necessary to fit in the rectangle).
  */

  int draw_text_rectangle(double xmin, double xmax,
			  double ymin, double ymax,
			  const char *text);

private:
  // dimensions of one subject page in the layout coordinate system
  double width_in_pixels;
  double height_in_pixels;
  // dots per pt for the layout
  double dppt;
  // number of pages created so far for current PDF file. Equals -1 if
  // no PDF file is opened for output
  int n_pages;
  // PDF document loaded (usualy the subject), from which one can copy
  // pages to the output PDF
  PopplerDocument *document;
  // Pango layout used to write texts
  PangoLayout *layout;
  // Cairo environment used to draw on the page
  cairo_surface_t *surface;
  cairo_t *cr;
  cairo_matrix_t matrix;
  // Cairo environment used to draw the background image (scan)
  cairo_t *image_cr;
  cairo_surface_t *image_surface;
  // Fake PNG image used to attach images to the PDF file. It will
  // never contain any particular image, only random stuff, but is
  // needed to attach images properly to the PDF output.
  unsigned char *fake_image_buffer;
  // Image currently been attached to the PDF output
  std::vector<uchar> image_buffer;
  // use this dimension in Cairo user coordinate system to get one
  // point (1/72 inch) in the PDF coordinate system
  double user_one_point;
  // scaling factor used to expand or shrink the scan to make it the
  // same size as the PDF output.
  double scan_expansion;
  // scaling factor used when resizing the scan (when its dimensions
  // exceed the scan_max_* values)
  double scan_resize_factor;

  // drawing parameters
  double margin;
  double line_width;
  std::string font;
  // debuging?
  int debug;
  // image parameters
  int embedded_image_format;
  int png_compression_level;
  int jpeg_quality;
  int scan_max_height;
  int scan_max_width;

  void set_matrix(double a, double b, double c ,double d, double e, double f);
  void set_matrix(cairo_matrix_t *m);

  double normalize_distance();
  double normalize_matrix_distance(cairo_matrix_t *m);
  PangoLayout* r_font_size_layout(double ratio);
  PangoFontDescription *font_description;
  int new_page_from_image_surface(cairo_surface_t *is);
  void draw_text(PangoLayout* local_layout,
		 double x, double y, double xpos, double ypos, const char *text);
  void free_buffer();
};

BuildPdf::~BuildPdf() {
  close_output();
  if(document != NULL) g_object_unref(document);
}

int BuildPdf::start_output(char* output_filename) {

  // close current PDF document, if one

  close_output();

  printf(": opening -> %s\n", output_filename);
  if(debug) {
    printf("; Create main surface\n");
  }

  // create a new PDF Cairo surface, with dimensions in points

  surface = cairo_pdf_surface_create(output_filename,
				     width_in_pixels / dppt,
				     height_in_pixels / dppt);

  cairo_status_t status = cairo_surface_status(surface);
  if(status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating surface - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(surface);
    surface = NULL;
    return(1);
  }

  // Create Cairo context for drawings and texts (will not be used for
  // images)

  if(debug) {
    printf("; Create cr\n");
  }
  cr = cairo_create(surface);

  if(cairo_status(cr) != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating cairo - %s\n",
	   cairo_status_to_string(cairo_status(cr)));
    cairo_surface_destroy(surface);
    cairo_destroy(cr);
    surface = NULL;
    cr = NULL;
    return(1);
  }

  // Create Pango Cairo layout for texts
  
  if(debug) {
    printf("; Create layout\n");
  }
  layout = pango_cairo_create_layout(cr);
  if(layout == NULL) {
     printf("! ERROR : creating pango/cairo layout - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(surface);
    cairo_destroy(cr);
    surface = NULL;
    cr = NULL;
    return(1);
  }

  // Updates the font description with the right font and uses it
  // for the new layout

  if(validate_font()) {
    return(2);
  }

  // initialization. user_one_point will be set when using set_matrix

  n_pages = 0;
  user_one_point = 0;

  if(debug) {  
    printf(": OK\n");
  }
  return(0);
}

void BuildPdf::close_output() {
  if(n_pages >= 0) {
    // free all allocated objects...

    printf(": closing...\n");
    next_page();
    cairo_surface_finish(surface);
    cairo_surface_destroy(surface);
    surface = NULL;
    cairo_destroy(cr);
    cr = NULL;
    if(image_cr != NULL) cairo_destroy(image_cr);
    image_cr = NULL;
    if(layout != NULL) {
      g_object_unref(layout);
      layout = NULL;
    }
    n_pages = -1;
  }
}

int BuildPdf::next_page() {
  if(n_pages<0) {
    printf("! ERROR: next_page in closed document\n");
    return(1);
  }
  if(n_pages >= 1) {

    // Adds current page to PDF output

    cairo_show_page(cr);
    if(debug) {
      printf("; Show page\n");
    }

    // Destroy objects used to insert the background scan

    if(image_cr != NULL) {
      if(debug) {
	printf("; Destroy image_cr\n");
      }
      cairo_destroy(image_cr);
      image_cr = NULL;
    }
    if(image_surface != NULL) {
      if(debug) {
	printf("; Destroy image_surface\n");
      }
      cairo_surface_finish(image_surface);
      cairo_surface_destroy(image_surface);
      image_surface = NULL;
    }
    if(fake_image_buffer != NULL) {
      free_buffer();
    }
    scan_resize_factor = 1.0;
    scan_expansion = 1.0;
  }

  n_pages++;
  return(0);
}

int BuildPdf::new_page_from_png(const char* filename) {
  if(next_page()) return(1);

  if(debug) {
    printf(": PNG < %s\n", filename);
    printf("; Create image_surface from PNG\n");
  }
  cairo_surface_t *is = cairo_image_surface_create_from_png(filename);
  return(new_page_from_image_surface(is));
}

int BuildPdf::new_page_from_png(void *buffer, unsigned long int buffer_length) {
  if(next_page()) return(1);

  buffer_closure closure;
  closure.buffer = (uchar*) buffer;
  closure.length = buffer_length;
  closure.offset = 0;

  if(debug) {
    printf(": PNG < BUFFER\n");
    printf("; Create image_surface from PNG stream\n");
  }
  cairo_surface_t *is = cairo_image_surface_create_from_png_stream(read_buffer, &closure);
  return(new_page_from_image_surface(is));
}

int BuildPdf::new_page_from_png(std::vector<uchar> &buf, int skip_show_page) {
  if(!skip_show_page) {
    if(next_page()) return(1);
  }

  vector_closure closure;
  closure.iterator = buf.begin();
  closure.length = buf.size();

  if(debug) {
    printf(": PNG < BUFFER\n");
    printf("; Create image_surface from PNG stream\n");
  }
  cairo_surface_t *is = cairo_image_surface_create_from_png_stream(read_vector, &closure);
  return(new_page_from_image_surface(is));
}

// Free buffer used for the fake image

void BuildPdf::free_buffer() {
  if(debug) {
    printf("; Free fake_image_buffer\n");
  }
  free(fake_image_buffer);
  fake_image_buffer = NULL;
}

void detach(void* args) {
  if(*((int*) args)) {
    printf("; DETACH\n");
  }
}

#define ZFORMAT CAIRO_FORMAT_A1
int BuildPdf::new_page_from_image(unsigned char *data, unsigned int size,
				  const char* mime_type,
				  int width, int height) {
  if(data == NULL) {
    printf("! ERROR : new_page_from_image from null data\n");
    return(1);
  }
  if(fake_image_buffer != NULL) {
    printf("! ERROR : fake_image_buffer already present\n");
    return(1);
  }
#ifdef DEBUG
  std::ofstream outfile("/tmp/opencv-exported", 
			std::ios::out | std::ios::binary);
  outfile.write((const char*) data, size);
#endif

  // Creates a fake image surface (to get minimal memory size, we use
  // CAIRO_FORMAT_A1 format) with associated memory buffer.

  int stride = cairo_format_stride_for_width(ZFORMAT, width);
  if(debug) {
    printf("; Create fake_image_buffer\n");
  }
  fake_image_buffer = (unsigned char*) malloc(stride * height);
  if(debug) {
    printf("; Create image_surface for DATA\n");
  }
  cairo_surface_t *is =
    cairo_image_surface_create_for_data(fake_image_buffer,
					ZFORMAT,
					width, height,
					stride);
  if(debug) {
    printf("; Attach mime %s to image_surface\n", mime_type);
  }

#if CAIRO_VERSION >= CAIRO_VERSION_ENCODE(1, 12, 0)
  if(!cairo_surface_supports_mime_type(surface, mime_type)) {
    printf("! ERROR: surface does not handle %s\n",
	   mime_type);
    return(1);
  }
#endif

  // Attach the real image to the surface

  cairo_status_t status =
    cairo_surface_set_mime_data(is, mime_type,
				data, size,
				detach, (void*) (&debug));
  if(status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : setting mime data - %s\n",
	   cairo_status_to_string(status));
    cairo_surface_destroy(is);
    free_buffer();
    return(-2);
  }

  // Uses the surface to create a new page
  
  int status_np = new_page_from_image_surface(is);
  return(status_np);
}

int BuildPdf::new_page_from_image(std::vector<uchar> &image_data,
				  const char* mime_type,
				  int width, int height) {
  return(new_page_from_image(image_data.data(), image_data.size(),
			     mime_type, width, height));
}

void BuildPdf::resize_scan(cv::Mat &image) {
  cv::Size s = image.size();

  // compute the resize factor to be used to get dimensions no more
  // than scan_max_*

  double fx = 2;
  double fy = 2;
  if(scan_max_width > 0) {
    fx = (double) scan_max_width / s.width;
  }
  if(scan_max_height > 0) {
    fy = (double) scan_max_height / s.height;
  }
  if(debug) {
    printf(": fx=%g fy=%g.\n", fx, fy);
  }
  if(fx < fy) {
    scan_resize_factor = fx;
  } else {
    scan_resize_factor = fy;
  }

  // resize the image if needed

  if(scan_resize_factor < 1.0) {
    cv::resize(image, image, cv::Size(),
	       scan_resize_factor, scan_resize_factor, cv::INTER_AREA);
  } else {
    scan_resize_factor = 1.0;
    if(debug) {
      printf(": No need to resize.\n");
    }
  }
}

int BuildPdf::new_page_from_image(const char* filename) {
  if(next_page()) return(1);

  int direct_png = 0;

  if(debug) {  
    printf(": IMAGE < %s\n", filename);
  }

  // read the image from disk to memory

  cv::Mat image = cv::imread(filename);
  const char* mime_type;

  if(debug) {  
    printf(": type=%d depth=%d channels=%d\n",
	   image.type(), image.depth(), image.channels());
  }

  // resize it if needed

  resize_scan(image);

  // encode the image to a PNG or JPEG image buffer

  if(embedded_image_format == FORMAT_JPEG) {
    std::vector<int> params;
    params.push_back(cv::IMWRITE_JPEG_QUALITY);
    params.push_back(jpeg_quality);
    imencode(".jpg", image, image_buffer, params);
    mime_type = CAIRO_MIME_TYPE_JPEG;
  } else if(embedded_image_format == FORMAT_PNG) {
    std::vector<int> params;
    params.push_back(cv::IMWRITE_PNG_COMPRESSION);
    params.push_back(png_compression_level);
    imencode(".png", image, image_buffer, params);
    mime_type = CAIRO_MIME_TYPE_PNG;
    direct_png = 1;
  } else {
    printf("! ERROR: invalid embedded_image_format - %d\n",
	   embedded_image_format);
    return(3);
  }
  
  cv::Size s = image.size();
  if(debug) {
    printf(": converted to %s [Q=%d C=%d] (%.1f KB) w=%d h=%d\n",
	   mime_type,
	   jpeg_quality, png_compression_level,
	   (double) image_buffer.size() / 1024,
	   s.width, s.height);
  }

  int r;
  if(direct_png) {
    // PNG images can't be "attached"
    // (cairo_surface_supports_mime_type would return FALSE), so we
    // directly insert them into the PDF output
    r = new_page_from_png(image_buffer, 1);
  } else {
    // JPEG images are attached to the image surface, and then
    // inserted to the PDF output
    r = new_page_from_image(image_buffer, mime_type, s.width, s.height);
  }

  if(debug) {
    printf("; Image buffer exit\n");
  }
  
  return(r);
}

int BuildPdf::new_page_from_image_surface(cairo_surface_t *is) {
  if(debug) {
    printf("; Entering new_page_from_image_surface\n");
  }
  if(image_surface != NULL) {
    printf("! ERROR : image_surface already in use\n");
    return(1);
  } else {
    if(is == NULL) {
      printf("! ERROR : NULL image_surface\n");
      return(1);
    }
    image_surface = is;
  }
  
  cairo_status_t image_surface_status = cairo_surface_status(image_surface);
  if(image_surface_status != CAIRO_STATUS_SUCCESS) {
    printf("! ERROR : creating image surface / %s\n",
	   cairo_status_to_string(image_surface_status));
    cairo_surface_destroy(image_surface);
    return(1);
  }
  int w = cairo_image_surface_get_width(image_surface);
  int h = cairo_image_surface_get_height(image_surface);
  if(w <= 0 || h <= 0) {
    printf("! ERROR : image dimensions should be positive (%dx%d)\n",
	   w, h);
    cairo_surface_destroy(image_surface);
    return(1);
  }
  
  // rx and ry are the scaling factors that has to be used to set the
  // image surface with the same dimensions as the PDF output

  double rx = width_in_pixels / dppt / w;
  double ry = height_in_pixels / dppt / h;

  if(rx < ry) {
    scan_expansion = rx;
  } else {
    scan_expansion = ry;
  }

  if(debug) {
    printf(": R=%g (%g,%g)\n", scan_expansion, rx, ry);
    printf("; Create and scale image_cr\n");
  }

  // Create the Cairo surface that will contain the image, with a
  // matrix that will scale the image to the PDF output dimensions

  image_cr = cairo_create(surface);

  cairo_identity_matrix(image_cr);
  cairo_scale(image_cr, scan_expansion, scan_expansion);

  if(debug) {
    printf("; set_source_surface\n");
  }

  // paint the image using context image_cr

  cairo_set_source_surface(image_cr, image_surface, 0, 0);
  if(debug) {
    printf("; paint from image_cr\n");
  }
  cairo_paint(image_cr);

  if(debug) {
    printf("; Exit new_page_from_image_surface: OK\n");
  }
  return(0);
}

int BuildPdf::load_pdf(char* filename) {
  GError *error = NULL;
  gchar *uri;

  if(document != NULL) g_object_unref(document);

  uri = g_filename_to_uri(filename, NULL, &error);
  if(uri == NULL) {
    printf("! ERROR: poppler fail: %s\n", error->message);
    return 1;
  }

  // loads the PDF document using Poppler

  document = poppler_document_new_from_file(uri, NULL, &error);
  if(document == NULL) {
    printf("! ERROR: poppler fail: %s\n", error->message);
    return 1;
  }

  identity_matrix();
  return(0);
}

int BuildPdf::new_page_from_pdf(int page_nb) {
  if(next_page()) {
    return(1);
  }

  if(document == NULL) {
    printf("! ERROR: no pdf loaded.\n");
    return(1);
  }

  // Inserts one page from pre-loaded PDF document, using
  // Poppler/Cairo

  PopplerPage *page = poppler_document_get_page(document, page_nb-1);
  if(page == NULL) {
    printf("! ERROR:poppler fail: page not found.\n");
    return 1;
  }
  cairo_identity_matrix(cr);
  poppler_page_render_for_printing(page, cr);
  g_object_unref(page);

  identity_matrix();
  return(0);
}

/* normalize_distance returns a user distance that will be mapped to a
   one point (=1/72 inch) distance on the PDF output, using current
   transformation matrix. */

double BuildPdf::normalize_distance() {
  double dx, dy;
  dx = 1.0;
  dy = 1.0;
  cairo_device_to_user_distance(cr, &dx, &dy);
  return( sqrt((dx * dx + dy * dy) / 2.0) );
}

/* the same, with any matrix */

double BuildPdf::normalize_matrix_distance(cairo_matrix_t *m) {
  double dx, dy;
  dx = 1.0;
  dy = 1.0;
  cairo_matrix_transform_distance(m, &dx, &dy);
  return( sqrt((dx * dx + dy * dy) / 2.0) );
}

void BuildPdf::set_line_width(double lw) {
  if(lw >= 0) {
    line_width = lw;
    if(line_width * user_one_point > 0) 
      cairo_set_line_width(cr, line_width * user_one_point);
  }
}

int BuildPdf::set_font(const char* f) {
  font = "";
  font.append(f);
  return(validate_font());
}

int BuildPdf::validate_font() {
  font_description = pango_font_description_from_string(font.c_str());
  if(font_description == NULL) {
    printf("! ERROR : font description creation\n");
    return(1);
  }
  pango_layout_set_font_description(layout, font_description);
  return(0);
}

/* r_font_size_layout creates a new Pango layout with a font size the
   is scaled with ratio.*/

PangoLayout* BuildPdf::r_font_size_layout(double ratio) {
  PangoLayout *local_layout = pango_layout_copy(layout);
  if(local_layout == NULL) {
    printf("! ERROR : creating local pango layout.\n");
    return(NULL);
  }
  const PangoFontDescription *desc = pango_layout_get_font_description(layout);
  if(desc == NULL) {
    printf("! ERROR : creating pango font description.\n");
    g_object_unref(local_layout);
    return(NULL);
  }
  gint size = pango_font_description_get_size(desc);
  PangoFontDescription *new_desc = pango_font_description_copy(desc);
  if(new_desc == NULL) {
    printf("! ERROR : creating local pango font description.\n");
    g_object_unref(local_layout);
    return(NULL);
  }
  if(pango_font_description_get_size_is_absolute(desc)) {
    pango_font_description_set_absolute_size(new_desc, size * ratio);
  } else {
    pango_font_description_set_size(new_desc, size * ratio);
  }
  pango_layout_set_font_description(local_layout, new_desc);
  return(local_layout);
}

/* cairo_matrix_scale_after makes the transformation matrix m to be
   composed with scaling with factor r, so that the resulting
   transformation is the same as 1) using matrix m 2) scaling. It
   seems from documentation that cairo_matrix_scale does it, but this
   is not: the resulting transformation with cairo_matrix_scale is the
   same as 1) scaling 2) using m.
*/

void cairo_matrix_scale_after(cairo_matrix_t *m, double r) {
  m->xx *= r;
  m->xy *= r;
  m->yx *= r;
  m->yy *= r;
  m->x0 *= r;
  m->y0 *= r;
}

/* same, but for a context matrix */

void cairo_scale_after(cairo_t *cr, double r) {
  cairo_matrix_t m;
  cairo_get_matrix(cr, &m);
  cairo_matrix_scale_after(&m, r);
  cairo_set_matrix(cr, &m);
}

/* set_matrix_to_scan gives the matrix that transforms layout
   coordinates to scan coordinates. This matrix is composed with a
   scaling so that layout coordinates are mapped to resized and
   expanded scan coordinates. Then, the matrix is used for drawings 
*/

void BuildPdf::set_matrix_to_scan(double a, double b, double c ,double d, double e, double f) {
  if(debug) {
    printf("; Set matrix to scan coordinates\n;   resize_factor=%g expansion=%g\n",
	   scan_resize_factor, scan_expansion);
  }

  cairo_matrix_init(&matrix, a, c, b, d, e, f);
  cairo_matrix_scale_after(&matrix, dppt * scan_resize_factor * scan_expansion);
  set_matrix(&matrix);
}

/* These two test_* functions are used for debugging */

void test_point(cairo_matrix_t *m, double x, double y) {
  double tx = x;
  double ty = y;
  printf(";   (%g,%g) ->", tx, ty);
  cairo_matrix_transform_point(m, &tx, &ty);
  printf(" (%g,%g)\n", tx, ty);
}

void test_matrix(cairo_matrix_t *m, double xmax, double ymax) {
  printf(";   x'=%7.3f x + %7.3f y + %6.3f\n", m->xx, m->xy, m->x0);
  printf(";   y'=%7.3f x + %7.3f y + %6.3f\n", m->yx, m->yy, m->y0);
  test_point(m, 0, 0);
  test_point(m, xmax, 0);
  test_point(m, 0, ymax);
  test_point(m, xmax, ymax);
}

void BuildPdf::set_matrix(double a, double b, double c ,double d, double e, double f) {
  if(debug) {
    printf("; Set matrix\n");
  }

  cairo_matrix_init(&matrix, a, c, b, d, e, f);
  set_matrix(&matrix);
}

/* set_matrix sets up transformations that will be used when
   drawing. The matrix m maps layout coordinates to pixel-based PDF
   coordinates. So it is scaled to get pt-based PDF coordinates before
   beeing used.
*/

void BuildPdf::set_matrix(cairo_matrix_t *m) {
  cairo_set_matrix(cr, m);
  cairo_scale_after(cr, 1 / dppt);

  // updates user_one_point, and the line width

  user_one_point = normalize_distance();
  set_line_width(line_width);

  // debugging...

  if(debug) {
    cairo_matrix_t ctm;
    cairo_get_matrix(cr, &ctm);
    double tx, ty;
    printf("; subject to scan matrix:\n");
    printf(";   dppt=%g\n", dppt);
    test_matrix(m, width_in_pixels, height_in_pixels);
    printf("; cr matrix:\n");
    printf(";   user 1pt=%g\n", user_one_point);
    test_matrix(&ctm, width_in_pixels, height_in_pixels);
  }
#ifdef DEBUG
  color(0.0, 0.5, 0.2, 0.5);
  draw_rectangle(0, width_in_pixels, 0, height_in_pixels);
#endif

  // updates Pango layout with new scaling factors
  pango_cairo_context_set_resolution(pango_layout_get_context(layout),
				     user_one_point * 72.);
  pango_cairo_update_layout(cr, layout);
  validate_font();
}

void BuildPdf::identity_matrix() {
  set_matrix(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
}

#define FIXX(xp) ((xp) - matrix.xy * *y - matrix.x0) / matrix.xx
void BuildPdf::keep_on_scan(double *x, double *y) {
  double xp = *x;
  double yp = *y;
  double margin_in_pixels = margin * dppt * 72.;
  cairo_matrix_transform_point(&matrix, &xp, &yp);
  if(xp < margin_in_pixels) {
    *x = FIXX(margin_in_pixels);
  } else if(xp > width_in_pixels - margin_in_pixels) {
    *x = FIXX(width_in_pixels - margin_in_pixels);
  }
}

void BuildPdf::draw_rectangle(double xmin, double xmax, double ymin, double ymax) {
  if(debug) {
    printf("; draw rectangle\n");
  }
  cairo_rectangle(cr, xmin, ymin, xmax - xmin, ymax - ymin);
  cairo_stroke(cr);
}

void BuildPdf::fill_rectangle(double xmin, double xmax, double ymin, double ymax) {
  if(debug) {
    printf("; fill rectangle\n");
  }
  cairo_rectangle(cr, xmin, ymin, xmax - xmin, ymax - ymin);
  cairo_fill(cr);
}

void BuildPdf::draw_mark(double xmin, double xmax, double ymin, double ymax) {
  if(debug) {
    printf("; draw mark\n");
  }
  cairo_move_to(cr, xmin, ymin);
  cairo_line_to(cr, xmax, ymax);
  cairo_move_to(cr, xmin, ymax);
  cairo_line_to(cr, xmax, ymin);
  cairo_stroke(cr);
}

void BuildPdf::draw_text(PangoLayout* local_layout,
			 double x, double y,
			 double xpos, double ypos,
			 const char *text) {
  if(debug) {
    printf("; draw text\n");
  }
  PangoRectangle extents;

  if(x<0) x += width_in_pixels;
  if(y<0) y += height_in_pixels;

  pango_layout_set_text(local_layout, text, -1);
  pango_layout_get_pixel_extents(local_layout, &extents, NULL);
  if(debug) {
    printf("TEXT=\"%s\" X=%d Y=%d W=%d H=%d\n",
	   text,
	   extents.x, extents.y,
	   extents.width, extents.height);
  }
  cairo_move_to(cr,
		x - xpos * extents.width - extents.x,
		y - ypos * extents.height - extents.y);
  pango_cairo_show_layout(cr, local_layout);
}

void BuildPdf::draw_text(double x, double y,
			 double xpos, double ypos,
			 const char *text) {
  draw_text(layout, x, y, xpos, ypos, text);
}

void BuildPdf::draw_text_margin(int xside, double y,
				double xpos, double ypos,
				const char *text) {
  double x;
  if(xside == 1) {
    x = width_in_pixels;
  } else {
    x = 0;
  }
  keep_on_scan(&x, &y);
  draw_text(x, y, xpos, ypos, text);
}

int BuildPdf::draw_text_rectangle(double xmin, double xmax,
				   double ymin, double ymax,
				   const char *text) {
  double r, rp;
  PangoRectangle extents;
  PangoLayout* local_layout;

  pango_layout_set_text(layout, text, -1);
  pango_layout_get_pixel_extents(layout, &extents, NULL);
  if(debug) {
    printf("TEXT=\"%s\" X=%d Y=%d W=%d H=%d\n",
	   text,
	   extents.x, extents.y,
	   extents.width, extents.height);
  }
  r = (xmax - xmin) / extents.width;
  rp = (ymax - ymin) / extents.height;
  if(rp < r) r = rp;
  if(debug) {
    printf(": ratio=%g\n", r);
  }

  local_layout = r_font_size_layout(r);
  if(local_layout == NULL) {
    printf("! ERROR: r_font_size_layout failed.");
    return(1);
  }
  draw_text(local_layout,
	    (xmin + xmax) / 2, (ymin + ymax) / 2,
	    0.5, 0.5, text);

  g_object_unref(local_layout);
  return(0);
}

void BuildPdf::draw_circle(double xmin, double xmax, double ymin, double ymax) {
  if(debug) {
    printf("; draw circle\n");
  }
  cairo_new_path(cr);
  cairo_arc(cr, (xmin + xmax) / 2, (ymin + ymax) / 2,
	    sqrt((xmax - xmin) * (xmax - xmin) + (ymax - ymin) * (ymax - ymin)) / 2,
	    0.0, 2 * M_PI);
  cairo_stroke(cr);
}

#endif
