/*

 Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>

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

#include <math.h>
#include <cstddef>

#include <stdio.h>
#include <locale.h>

#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <errno.h>

#ifdef NEEDS_GETLINE
  #include <minimal-getline.c>
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
  #ifdef AMC_DETECT_HIGHGUI
    #include "opencv2/highgui/highgui.hpp"
  #endif
#else
  #include "opencv2/highgui/highgui.hpp"
#endif

using namespace std;

int processing_error = 0;

/*
  Note:

  IMAGE COORDINATES: (0,0) is upper-left corner
*/

#define GET_PIXEL(src,x,y) *((uchar*)(src.data+src.step*(y)+src.channels()*(x)))
#define PIXEL(src,x,y) GET_PIXEL(src,x,y)>100

#define RGB_COLOR(r,g,b) cv::Scalar((b),(g),(r),0)

#define BLEU RGB_COLOR(38,69,223)
#define ROSE RGB_COLOR(223,38,203)

#define SWAP(x,y,tmp) tmp=x;x=y;y=tmp
#define SGN_ROT (1-2*upside_down)
#define SUM_SQUARE(x,y) ((x)*(x)+(y)*(y))
#define SHAPE_SQUARE 0
#define SHAPE_OVAL 1

#define DIR_X 1
#define DIR_Y 2

#define ILLUSTR_BOX 1
#define ILLUSTR_PIXELS 2

/*

   the following functions select, from a points sequence, four
   extreme points:

   - the most NW one with coordinates (corner_x[0],corner_y[0]),
   - the most NE one with coordinates (corner_x[1],corner_y[1]),
   - the most SE one with coordinates (corner_x[2],corner_y[2]),
   - the most SW one with coordinates (corner_x[3],corner_y[3]),

   First call

   agrege_init(image_width,image_height,corners_x,corners_y)

   which will initialize the extreme points coordinates, and then

   agrege(x,y)

   for all points (x,y) from the sequence.

 */

void agrege_init(double tx,double ty,double* coins_x,double* coins_y) {
  coins_x[0] = tx; coins_y[0] = ty;
  coins_x[1] = 0;  coins_y[1] = ty;
  coins_x[2] = 0;  coins_y[2] = 0;
  coins_x[3] = tx; coins_y[3] = 0;
}

#define AGREGE_POINT(op,comp,i) if((x op y) comp (coins_x[i] op coins_y[i])) { coins_x[i]=x;coins_y[i]=y; }

void agrege(double x,double y,double* coins_x,double* coins_y) {
  AGREGE_POINT(+,<,0)
  AGREGE_POINT(+,>,2)
  AGREGE_POINT(-,>,1)
  AGREGE_POINT(-,<,3)
}

/*

  load_image(...) loads the scan image, with some pre-processings:

  - if ignore_red is true, the red color is discarder from the scan:
    only the red channel is kept from the scan.

  - the image is (a little) smoothed with a Gaussian kernel, and a
    threshold is applied to convert the image from greyscale to
    black&white only. The threshold value is MAX*threshold, where MAX
    is the maximum value for all pixels (that is the grey value for
    the lighter pixel), and threshold is given to load_image as a
    parameter.

  - the image is flipped if necessary to get the upper-left pixel at
    coordinates (0,0)

  The result image is *src.

*/

void load_image(cv::Mat &src,char *filename,
                int ignore_red,double threshold=0.6,int view=0) {
  cv::Mat color;
  double max;

  if(ignore_red) {
    printf(": loading red channel from %s ...\n", filename);
    try {
      color = cv::imread(filename,
#ifdef OPENCV_23
			 cv::IMREAD_ANYCOLOR
#else
			 cv::IMREAD_UNCHANGED
#endif
			 );
    } catch (const cv::Exception& ex) {
      printf("! LOAD : Error loading scan file in ANYCOLOR [%s]\n", filename);
      printf("! OpenCV error: %s\n", ex.what());
      processing_error = 3;
      return;
    }
    if(color.channels() >= 3) {
      // 'src' will only keep the red channel.
      src = cv::Mat(color.rows, color.cols,
		    CV_MAKETYPE(color.depth(), 1 /* 1 channel for red */));

      // Take the red channel (2) from 'color' and put it in the
      // only channel of 'src' (0).
      int from_to[] = {2,0};
      cv::mixChannels(&color, 1, &src, 1, from_to, 1);
      color.release();
    } else if(color.channels() != 1) {
      printf("! LOAD : Scan file with 2 channels [%s]\n", filename);
      processing_error = 2;
      return;
    } else {
      src = color;
    }
  } else {
    printf(": loading %s ...\n", filename);
    try {
      src = cv::imread(filename, cv::IMREAD_GRAYSCALE);
    } catch (const cv::Exception& ex) {
      printf("! LOAD : Error loading scan file in GRAYSCALE [%s]\n", filename);
      printf("! OpenCV error: %s\n", ex.what());
      processing_error = 3;
      return;
    }
  }

  cv::minMaxLoc(src, NULL, &max);
  printf(": Image max = %.3f\n", max);
  cv::GaussianBlur(src, src, cv::Size(3,3), 1);
  cv::threshold(src, src, max*threshold, 255, cv::THRESH_BINARY_INV);
}

/*

  pre_traitement(...) tries to remove scan artefacts (dust and holes)
  from image *src, using morphological closure and opening.

  - lissage_trous is the radius of the holes to remove (in pixels)
  - lissage_poussieres is the radius of the dusts to remove (in pixels)

*/

void pre_traitement(cv::Mat &src,int lissage_trous,int lissage_poussieres) {
  printf("Morph: +%d -%d\n", lissage_trous, lissage_poussieres);
  cv::Mat trous = cv::getStructuringElement(
      cv::MORPH_ELLIPSE,
      cv::Size(1 + 2 * lissage_trous, 1 + 2 * lissage_trous),
      cv::Point(lissage_trous, lissage_trous));

  cv::Mat poussieres = cv::getStructuringElement(
      cv::MORPH_ELLIPSE,
      cv::Size(1 + 2 * lissage_poussieres, 1 + 2 * lissage_poussieres),
      cv::Point(lissage_poussieres, lissage_poussieres));

  cv::morphologyEx(src, src, cv::MORPH_CLOSE, trous);
  cv::morphologyEx(src, src, cv::MORPH_OPEN, poussieres);

  trous.release();
  poussieres.release();
}

/* LINEAR TRANSFORMS */

/* the linear_transform  structure contains a linear transform
   x'=ax+by+e
   y'=cx+dy+f
*/

typedef struct {
  double a,b,c,d,e,f;
} linear_transform;

/* transforme(t,x,y,&xp,&yp) applies the linear transform t to the
   point (x,y) to give (xp,yp)
*/

void transforme(linear_transform* t,double x,double y,double* xp,double* yp) {
  *xp = t->a * x + t->b * y + t->e;
  *yp = t->c * x + t->d * y + t->f;
}

/* POINTS AND LINES */

/* point structure */

typedef struct {
  double x,y;
} point;

/* line structure (through its equation ax+by+c=0) */

typedef struct {
  double a,b,c;
} ligne;

/* calcule_demi_plan(...) computes the equation of line (AB) from the
   coordinates *a of A and *b of B, and stores it to *l.
*/

void calcule_demi_plan(point *a,point *b,ligne *l) {
  double vx,vy;
  vx = b->y - a->y;
  vy = -(b->x - a->x);
  l->a = vx;
  l->b = vy;
  l->c = - a->x*vx - a->y*vy;
}

/* evalue_demi_plan(...) computes the sign of ax+by+c from line
   *equation l, giving which side of l the point at (x,y) is.
*/

int evalue_demi_plan(ligne *l,double x,double y) {
  return l->a * x + l->b * y + l->c <= 0 ? 1 : 0;
}

/* VECTOR ARITHMETIC */

/* moyenne(x[],n) returns the mean of the n values from vector x[]
*/

double moyenne(double *x, int n, int omit=-1) {
  double s = 0;
  for(int i = 0; i < n; i++) {
    if(i != omit) {
        s += x[i];
    }
  }
  return s / (n - (omit >= 0 ? 1 : 0));
}

/* scalar_product(x[],y[],n) returns the scalar product of vectors x[]
   and y[] (both of size n), that is the sum over i of x[i]*y[i].
*/

double scalar_product(double *x,double *y,int n, int omit=-1) {
  double sx = 0, sy = 0, sxy = 0;
  for(int i = 0; i < n; i++) {
    if(i != omit) {
      sx += x[i];
      sy += y[i];
      sxy += x[i]*y[i];
    }
  }
  if(omit>=0)
      n--;
  return sxy/n - sx/n * sy/n;
}

/* sys_22(...) solves the 2x2 linear system

   ax+by+e=0
   cx+dy+f=0

   and sets *x and *y with the solution. If the system is
   not-invertible, *x and *y are left unchanged and a warning is
   printed out.
*/

void sys_22(double a,double b,double c,double d,double e,double f,
              double *x,double *y) {
  double delta = a*d - b*c;
  if(delta == 0) {
    printf("! NONINV : Non-invertible system.\n");
    return;
  }
  *x = (d*e - b*f) / delta;
  *y = (a*f - c*e) / delta;
}

/* square of x */

double sqr(double x) { return(x*x); }

/* LINEAR TRANSFORM OPTIMIZATION */

/* revert_transform(...) computes the inverse transform of *direct,
   and stores it to *back.
*/

void revert_transform(linear_transform *direct,
                      linear_transform *back) {
  double delta = direct->a * direct->d - direct->b * direct->c;
  if(delta == 0) {
    printf("! NONINV : Non-invertible system.\n");
    return;
  }
  back->a = direct->d / delta;
  back->b = - direct->b / delta;
  back->e = (direct->b * direct->f - direct->e * direct->d) / delta;

  back->c = - direct->c / delta;
  back->d = direct->a / delta;
  back->f = (direct->e * direct->c - direct->a * direct->f) / delta;

  printf("Back:\na'=%f\nb'=%f\nc'=%f\nd'=%f\ne'=%f\nf'=%f\n",
         back->a, back->b,
         back->c, back->d,
         back->e, back->f);
}

/* optim(...) computes the linear transform T such that the sum S of
   square distances from T(M[i]) to MP[i] is minimal, where M[] and
   MP[] are sequences of n points.

   points_x[] and points_y[] are the coordinates of the points M[],
   and points_xp[] and points_yp[] are the coordinates of the points
   M[].

   The return value is the mean square error (square root of S/n).
*/

double optim(double* points_x,double* points_y,
             double* points_xp,double* points_yp,
             int n,
             linear_transform* t,
             int omit=-1) {
  double sxx = scalar_product(points_x, points_x, n, omit);
  double sxy = scalar_product(points_x, points_y, n, omit);
  double syy = scalar_product(points_y, points_y, n, omit);

  double sxxp = scalar_product(points_x, points_xp, n, omit);
  double syxp = scalar_product(points_y, points_xp, n, omit);
  double sxyp = scalar_product(points_x, points_yp, n, omit);
  double syyp = scalar_product(points_y, points_yp, n, omit);

  sys_22(sxx, sxy, sxy, syy, sxxp, syxp, &(t->a), &(t->b));
  sys_22(sxx, sxy, sxy, syy, sxyp, syyp, &(t->c), &(t->d));
  t->e = moyenne(points_xp,n,omit)
    - (t->a * moyenne(points_x,n,omit) + t->b*moyenne(points_y,n,omit));
  t->f = moyenne(points_yp,n,omit)
    - (t->c * moyenne(points_x,n,omit) + t->d*moyenne(points_y,n,omit));

  double mse = 0;
  for(int i = 0; i < n; i++) {
    if(i != omit) {
      mse += sqr(points_xp[i] - (t->a * points_x[i] + t->b * points_y[i] + t->e));
      mse += sqr(points_yp[i] - (t->c * points_x[i] + t->d * points_y[i] + t->f));
    }
  }
  mse = sqrt(mse / (n - (omit <= 0 ? 1 : 0)));
  return mse;
}

/* transform_quality(&t) returns a "square distance" from the
   transform t to an exact orthonormal transform.
*/
double transform_quality_2(linear_transform* t) {
  return SUM_SQUARE(t->c+t->b,t->d-t->a) / SUM_SQUARE(t->a,t->b);
}

/* omit_optim(...) tries an optim() call omitting in turn one of the
   points, and returns the best transform (the more "orthonormal"
   one).
*/
double omit_optim(double* points_x, double* points_y,
                  double* points_xp, double* points_yp,
                  int n,
                  linear_transform* t) {
  linear_transform t_best;
  double q, q_best;
  int i_best = -1;
  for(int i = 0; i < n; i++) {
    optim(points_x, points_y, points_xp, points_yp, n, t, i);
    q = transform_quality_2(t);
    printf("OMIT_CORNER=%d Q2=%lf\n", i, q);
    if(i_best < 0 || q < q_best) {
      i_best = i;
      q_best = q;
      memcpy((void*)&t_best, (void*)t, sizeof(linear_transform));
    }
  }
  memcpy((void*)t, (void*)&t_best, sizeof(linear_transform));
  return sqrt(q_best);
}

/* calage(...) tries to detect the position of a page on a scan.

 - *src is the scan image (comming from load_image).

 - if illustr is not NULL, a rectangle is drawn on image *illustr to
   show where the corner marks (circles) has been detected.

 - taille_orig_x and taille_orig_y are the width and height of the
   model page.

 - dia_orig is the diameter of the corner marks (circles) on the model
   page.

 - tol_plus and tol_moins are tolerence ratios for corner marks:
   calage will look for marks with diameter between
   dia_orig*(1-tol_moins) and dia_orig*(1+tol_plus) (scaled to scan
   size).

 - coins_x[] and coins_y[] will be filled with the coordinates of the
   4 corner marks detected on the scan.

 - if view==1, a report image *dst will be created to show all
   connected components from source image that has correct diameter.

 - if view==2, a report image *dst will be created from the source
   image with over-printed connected components with correct diameter.

 1) pre_traitement is called to remove dusts and holes.

 2) cvFindContours find the connected components from the image. All
 connected components with diameter too far from target diameter (see
 tol_plus and tol_moins parameters) are discarded.

 3) the centers of the extreme connected components with correct
 diameter are returned.

*/

void calage(cv::Mat src, cv::Mat illustr,
            double taille_orig_x, double taille_orig_y,
            double dia_orig,
            double tol_plus, double tol_moins,
            int n_min_cc,
            double* coins_x, double *coins_y,
            cv::Mat &dst,int view=0) {
  cv::Point coins_int[4];
  int n_cc;

  /* computes target min and max size */

  double rx = src.cols / taille_orig_x;
  double ry = src.rows / taille_orig_y;
  double target = dia_orig * (rx + ry) / 2;
  double target_max = target * (1 + tol_plus);
  double target_min = target * (1 - tol_moins);

  /* 1) remove holes that are smaller than 1/8 times the target mark
     diameter, and dusts that are smaller than 1/20 times the target
     mark diameter.
  */

  pre_traitement(src,
                 1 + (int)((target_min+target_max)/2 /20),
                 1 + (int)((target_min+target_max)/2 /8));

  if(view == 2) {
    /* prepares *dst from a copy of the scan (after pre-processing). */
    dst = cv::Mat(cv::Size(src.rows, src.cols), CV_MAKETYPE(CV_8U, 3));

    // cvConvertImage(src, *dst) is not needed anymore as 'src' and 'dst' have
    // the same type.
    cv::bitwise_not(dst,dst);
  }

  printf("Target size: %.1f ; %.1f\n", target_min, target_max);

  /* 2) find connected components */

  // CvSeq* contour = 0;
  vector<vector<cv::Point> > contours;
  vector<cv::Vec4i> hierarchy; // unused; but could be used in drawContours
  cv::findContours(src, contours, hierarchy, cv::RETR_CCOMP, cv::CHAIN_APPROX_SIMPLE);

#ifdef OPENCV_21
  if(view == 1) {
    /* prepares *dst as a white image with same size as the scan. */
    dst = cv::Mat::zeros(cv::Size(src.rows, src.cols), CV_MAKETYPE(src.depth(), 3));
  }
#endif

  /* 3) returns the result, and draws reports */

  agrege_init(src.cols, src.rows, coins_x, coins_y);
  n_cc = 0;

  printf("Detected connected components:\n");

  for(int i = 0; i < contours.size(); i++) {
    cv::Rect rect = cv::boundingRect(cv::Mat(contours[i]));
    /* discard the connected components that are too large or too small */
    if(rect.width <= target_max && rect.width >= target_min &&
       rect.height <= target_max && rect.height >= target_min) {
      /* updates the extreme points coordinates from the coordinates
         of the center of the connected component. */
      agrege(rect.x + (rect.width - 1) / 2.0,
             rect.y + (rect.height - 1) / 2.0,
             coins_x,
             coins_y);

      /* outputs connected component center and size. */
      printf("(%d;%d)+(%d;%d)\n",
             rect.x, rect.y, rect.width, rect.height);
      n_cc++;

#ifdef OPENCV_21
     if(view == 1) {
       /* draws the connected component, and the enclosing rectangle,
          with a random color. */
        cv::Scalar color = RGB_COLOR(rand() & 255, rand() & 255, rand() & 255);
        cv::rectangle(dst, cv::Point(rect.x,rect.y), cv::Point(rect.x+rect.width,rect.y+rect.height), color);
        cv::drawContours(dst, contours, i, color, cv::FILLED);
      }
#endif
     if(view==2) {
       /* draws the connected component, and the enclosing rectangle,
          in green. */
        cv::Scalar color = RGB_COLOR(60,198,127);
        cv::rectangle(dst, cv::Point(rect.x,rect.y), cv::Point(rect.x+rect.width,rect.y+rect.height), color);
        cv::drawContours(dst, contours, i, color, cv::FILLED);
     }
    }
  }

  if(n_cc >= n_min_cc) {
    for(int i = 0; i < 4; i++) {
      /* computes integer coordinates of the extreme coordinates, for
         later drawings */
      if(view > 0 || illustr.data != NULL) {
        coins_int[i].x = (int)coins_x[i];
        coins_int[i].y = (int)coins_y[i];
      }
      /* outputs extreme points coordinates: the (supposed)
         coordinates of the marks on the scan. */
      printf("Frame[%d]: %.1f ; %.1f\n", i, coins_x[i], coins_y[i]);
    }

    if(view==1) {
#ifdef OPENCV_21
      /* draws a rectangle to see the corner marks positions on the scan. */
      for(int i = 0; i < 4; i++) {
        cv::line(dst, coins_int[i], coins_int[(i+1)%4], RGB_COLOR(255,255,255), 1, cv::LINE_AA);
      }
#endif
    }
    if(view==2) {
      /* draws a rectangle to see the corner marks positions on the scan. */
      for(int i = 0; i < 4; i++) {
        cv::line(dst, coins_int[i], coins_int[(i+1)%4], RGB_COLOR(193,29,27), 1, cv::LINE_AA);
      }
    }

    if(illustr.data!=NULL) {
      /* draws a rectangle to see the corner marks positions on the scan. */
      for(int i = 0; i < 4; i++) {
        cv::line(illustr, coins_int[i], coins_int[(i+1)%4], BLEU, 1, cv::LINE_AA);
      }
    }
  } else {
    /* There are less than 3 correct connected components: can't know
       where are the marks on the scan! */
    printf("! NMARKS=%d : Not enough marks detected.\n", n_cc);
  }
}

/* moves A and B to each other, proportion delta of the distance
   between A and B -- here only one coordinate is processed: cn is 'x'
   or 'y'.

   d is a temporary variable.
*/

#define CLOSER(pointa,pointb,cn,dist,delta) dist=delta*(pointb.cn-pointa.cn);pointa.cn+=dist;pointb.cn-=dist;

/* deplace(...) moves coins[i] and coins[j] to each other */

void deplace(int i,int j,double delta,point *coins) {
  double d;
  CLOSER(coins[i], coins[j],x, d, delta);
  CLOSER(coins[i], coins[j],y, d, delta);
}

/* deplace_xy(...) moves two real numbers *m1 and *m2 to each other,
   proportion delta of the distance between them.
*/

void deplace_xy(double *m1,double *m2,double delta) {
  double d = (*m2-*m1) * delta;
  *m1 += d;
  *m2 -= d;
}

/* restreint(...) ensures that the point (*x,*y) is inside the image,
   moving it inside if necessary.

   tx and ty are the width and height of the image.
*/

void restreint(int *x,int *y,int tx,int ty) {
  if(*x < 0) *x = 0;
  if(*y < 0) *y = 0;
  if(*x >= tx) *x = tx - 1;
  if(*y >= ty) *y = ty - 1;
}

/* if student>=0, check_zooms_dir(...) checks that the zoom directory
   zooms_dir (for student number given as a parameter) exists, or
   tries to create it.

   In case of problem, error message is printer to STDOUT.

   if log is true, some more messages are printed.
*/

int check_zooms_dir(int student, char *zooms_dir=NULL,int log=0) {
  int ok = 1;
  struct stat zd;

  if(student >= 0) {
    if(stat(zooms_dir,&zd) != 0) {
      if(errno == ENOENT) {
        if(mkdir(zooms_dir,0755) != 0) {
          ok = 0;
          printf("! ZOOMDC : Zoom dir creation error %d : %s\n", errno, zooms_dir);
        } else {
          printf(": Zoom dir created %s\n", zooms_dir);
        }
      } else {
        ok = 0;
        printf("! ZOOMDS : Zoom dir stat error %d : %s\n", errno, zooms_dir);
      }
    } else {
      if(!S_ISDIR(zd.st_mode)) {
        ok = 0;
        printf("! ZOOMDP : Zoom dir is not a directory : %s\n", zooms_dir);
      }
    }
  } else {
    ok = 0;
    if(log) {
      printf(": No zoom dir to create (student<0).\n");
    }
  }
  return ok;
}

/* mesure_case(...) computes the darkness value (number of black
   pixels, and total number of pixels) of a particular box on the
   scan. A "zoom" (small image with the box on the scan only) can be
   extracted in order to have a closer look at the scaned box later.

   - *src is the source black&white image.

   - *illustr is an image on which drawings will be made:

     with illustr_mode==ILLUSTR_BOX, a blue rectangle shows the box
     position, and a pink rectangle shows the measuring box (a box a
     little smaller than the box itself).

     with illustr_mode==ILLUSTR_PIXELS, all measured pixels will be
     coloured (black pixels in green, and white pixels in blue)

   - student is the student number. student<0 means that the student
     number is not yet known (we are measuring the ID binary boxes to
     detect the page and student numbers), so that zooms are extracted
     only when student>=0

   - page is the page number (unused)

   - question,answer are the question and answer numbers for the box
     beeing measured. These are used to build a zoom file name from
     the template zooms_dir/question-answer.png

   - prop is a ratio that is used to reduce the box before measuring
     how many pixels are black (the goal here is to try to avoid
     measuring the border of the box, that are always dark...). It
     should be small (0.1 seems to be reasonable), otherwise only a
     small part in the center of the box will be considered -- but not
     too small, otherwise the border of the box could be taken into
     account, so that the measures are less reliable to determine if a
     box is ticked or not.

   - shape_id is the shape id of the box: SHAPE_OVAL or SHAPE_SQUARE.

   - o_xmin,o_xmax,o_ymin,o_ymax are the box coordinates on the
     original subject. NOTE: if o_xmin<0, the box coordinates on the
     scan are not given through these variables values, but directly
     in the coins[] variables.

   - transfo_back is the optimal linear transform that gets
     coordinates on the scan to coordinates on the original
     subject. NOTE: only used if o_xmin>=0.

   - coins[] will be filled with the coordinates of the 4 corners of
     the measuring box on the scan. NOTE: if o_xmin<0, coins[]
     contains as an input the coordinates of 4 corners of the box on
     the scan.

   - some reports will be drawn on *dst:

     if view==1, the measuring boxes will be drawn.

   - zooms_dir is the directory path where to store zooms extracted
     from the *src image.

*/

void mesure_case(cv::Mat src, cv::Mat illustr,int illustr_mode,
                 int student,int page,int question, int answer,
                 double prop,int shape_id,
                 double o_xmin,double o_xmax,double o_ymin,double o_ymax,
                 linear_transform *transfo_back,
                 point *coins, cv::Mat &dst,
                 char *zooms_dir=NULL,int view=0) {
  int npix, npixnoir, xmin, xmax, ymin, ymax, x, y;
  int z_xmin, z_xmax, z_ymin, z_ymax;
  ligne lignes[4];
  int i, ok;
  double delta;
  double o_x, o_y;
  cv::Scalar pixel;

  double ov_r, ov_r2, ov_dir, ov_center, ov_x0, ov_x1, ov_y0, ov_y1;

  int tx = src.cols;
  int ty = src.rows;

  cv::Point coins_int[4];

  static char* zoom_file = NULL;

#if OPENCV_20
  vector<int> save_options;
  save_options.push_back(cv::IMWRITE_PNG_COMPRESSION);
  save_options.push_back(7);
#endif

  npix = 0;
  npixnoir = 0;

  if(illustr.data != NULL) {
    for(int i = 0; i < 4; i++) {
      coins_int[i].x = (int)coins[i].x;
      coins_int[i].y = (int)coins[i].y;
    }

    if(illustr_mode == ILLUSTR_BOX) {
      /* draws the box on the illustrated image (for zoom) */
      for(int i = 0; i < 4; i++) {
        cv::line(illustr, coins_int[i], coins_int[(i+1)%4], BLEU, 1, cv::LINE_AA);
      }
    }

    /* bounding box for zoom */
    z_xmin = tx - 1;
    z_xmax = 0;
    z_ymin = ty - 1;
    z_ymax = 0;
    for(int i = 0; i < 4; i++) {
      if(coins_int[i].x < z_xmin) z_xmin = coins_int[i].x;
      if(coins_int[i].x > z_xmax) z_xmax = coins_int[i].x;
      if(coins_int[i].y < z_ymin) z_ymin = coins_int[i].y;
      if(coins_int[i].y > z_ymax) z_ymax = coins_int[i].y;
    }

    /* a little bit larger... */
    int delta = (z_xmax - z_xmin + z_ymax - z_ymin) / 20;
    z_xmin -= delta;
    z_ymin -= delta;
    z_xmax += delta;
    z_ymax += delta;
  }

  /* box reduction */
  delta = (1 - prop) / 2;
  deplace(0, 2, delta, coins);
  deplace(1, 3, delta, coins);

  deplace_xy(&o_xmin, &o_xmax, delta);
  deplace_xy(&o_ymin, &o_ymax, delta);

  /* output points used for mesuring */
  for(i = 0; i < 4; i++) {
    printf("COIN %.3f,%.3f\n",coins[i].x,coins[i].y);
  }

  /* bounding box */
  xmin = tx - 1;
  xmax = 0;
  ymin = ty - 1;
  ymax = 0;
  for(i = 0; i < 4; i++) {
    if(coins[i].x < xmin) xmin = (int)coins[i].x;
    if(coins[i].x > xmax) xmax = (int)coins[i].x;
    if(coins[i].y < ymin) ymin = (int)coins[i].y;
    if(coins[i].y > ymax) ymax = (int)coins[i].y;
  }

  restreint(&xmin, &ymin, tx, ty);
  restreint(&xmax, &ymax, tx, ty);

  if(o_xmin < 0) {
    /* computes half planes equations */
    calcule_demi_plan(&coins[0], &coins[1], &lignes[0]);
    calcule_demi_plan(&coins[1], &coins[2], &lignes[1]);
    calcule_demi_plan(&coins[2], &coins[3], &lignes[2]);
    calcule_demi_plan(&coins[3], &coins[0], &lignes[3]);
  } else {
    if(shape_id == SHAPE_OVAL) {
      if(o_xmax-o_xmin < o_ymax-o_ymin) {
        /* vertical oval */
        ov_dir = DIR_Y;
        ov_r = (o_xmax - o_xmin) / 2;
        ov_x0 = o_xmin;
        ov_x1 = o_xmax;
        ov_y0 = o_ymin + ov_r;
        ov_y1 = o_ymax - ov_r;
        ov_center = (o_xmin + o_xmax) / 2;
      } else {
        /* horizontal oval */
        ov_dir = DIR_X;
        ov_r = (o_ymax - o_ymin) / 2;
        ov_x0 = o_xmin + ov_r;
        ov_x1 = o_xmax - ov_r;
        ov_y0 = o_ymin;
        ov_y1 = o_ymax;
        ov_center = (o_ymin + o_ymax) / 2;
      }
      ov_r2 = ov_r * ov_r;
    }
  }

  for(x = xmin; x <= xmax; x++) {
    for(y = ymin; y <= ymax; y++) {
      if(o_xmin < 0) {
        /* With "mesure" command, checks if this point is in the box
           or not from the scan coordinates (x,y) */
        ok = 1;
        for(i = 0; i < 4; i++) {
          if(evalue_demi_plan(&lignes[i], (double)x, (double)y) == 0)
              ok = 0;
        }
      } else {
        /* With "mesure0" command, computes the coordinates in the
           original image with transfo_back, and then check if the
           point is in the box (this is easier since this box has
           edges parallel to coordinate axis) */
        transforme(transfo_back, (double)x, (double)y, &o_x, &o_y);
        if(shape_id == SHAPE_OVAL) {
          if(ov_dir == DIR_X) {
            if(o_x <= ov_x0) {
              ok = (SUM_SQUARE(o_x - ov_x0, o_y - ov_center) <= ov_r2);
            } else if(o_x>=ov_x1) {
              ok = (SUM_SQUARE(o_x - ov_x1, o_y - ov_center) <= ov_r2);
            } else {
              ok = (o_y>=ov_y0 && o_y<=ov_y1);
            }
          } else {
            if(o_y<=ov_y0) {
              ok = (SUM_SQUARE(o_y - ov_y0, o_x - ov_center) <= ov_r2);
            } else if(o_y>=ov_y1) {
              ok = (SUM_SQUARE(o_y - ov_y1, o_x - ov_center) <= ov_r2);
            } else {
              ok = (o_x >= ov_x0 && o_x <= ov_x1);
            }
          }
        } else {
          ok = !(o_x < o_xmin || o_x > o_xmax || o_y < o_ymin || o_y > o_ymax);
        }
      }
      if(ok == 1) {
        npix++;
        if(PIXEL(src,x,y))
            npixnoir++;
        if(illustr.data != NULL && illustr_mode == ILLUSTR_PIXELS) {
          /* with option -k, colors (on the zooms) pixels that are
             taken into account while computing the darkness ratio of
             the boxes */
          illustr.ptr<uchar>(y)[x*3] = (PIXEL(src,x,y) ? 0 : 255);
          illustr.ptr<uchar>(y)[x*3 + 1] = 128;
          illustr.ptr<uchar>(y)[x*3 + 2] = 0;
        }
      }
    }
  }

  if(view == 1 || illustr.data != NULL) {
    for(int i = 0; i < 4; i++) {
      coins_int[i].x = (int)coins[i].x;
      coins_int[i].y = (int)coins[i].y;
    }
  }
#ifdef OPENCV_21
  if(view == 1) {
    for(int i = 0; i < 4; i++) {
      cv::line(dst, coins_int[i], coins_int[(i+1)%4], RGB_COLOR(255,255,255), 1, cv::LINE_AA);
    }
  }
#endif
  if(illustr.data != NULL) {

    if(illustr_mode == ILLUSTR_BOX) {
      /* draws the measuring box on the illustrated image (for zoom) */
      for(int i = 0; i < 4; i++) {
        cv::line(illustr, coins_int[i], coins_int[(i+1)%4], ROSE, 1, cv::LINE_AA);
      }
    }

    /* making zoom */

    if(zooms_dir != NULL && student >= 0) {

      /* check if directory is present, or ceate it */
      ok = check_zooms_dir(student, zooms_dir, 0);

      /* save zoom file */
      if(ok) {
        if(asprintf(&zoom_file, "%s/%d-%d.png", zooms_dir, question, answer)>0) {
          printf(": Saving zoom to %s\n", zoom_file);
          printf(": Z=(%d,%d)+(%d,%d)\n",
                 z_xmin, z_ymin, z_xmax - z_xmin, z_ymax - z_ymin);
          cv::Mat roi = illustr(cv::Rect(z_xmin, z_ymin, z_xmax - z_xmin, z_ymax - z_ymin));

	  bool result = false;
	  try {
	    result = cv::imwrite(zoom_file, roi
#if OPENCV_20
				 , save_options
#endif
				 );
	  } catch (const cv::Exception& ex) {
            printf("! ZOOMS : Zoom save error: %s\n", ex.what());
          }
	  if(result)
	    printf("ZOOM %d-%d.png\n", question, answer);

        } else {
          printf("! ZOOMFN : Zoom file name error\n");
        }
      }
    }
  }

  printf("PIX %d %d\n", npixnoir, npix);
}

/* MAIN

   Processes command-line parameters, and then reads commands from
   standard input, and answers them on standard output.

*/

int main(int argc, char** argv)
{
  if(! setlocale(LC_ALL, "POSIX")) {
    printf("! LOCALE : setlocale failed\n");
  }

  double threshold = 0.6;
  double taille_orig_x = 0;
  double taille_orig_y = 0;
  double dia_orig = 0;
  double tol_plus = 0;
  double tol_moins = 0;
  int n_min_cc = 3;

  double prop, xmin, xmax, ymin, ymax;
  double coins_x[4], coins_y[4];
  double coins_x0[4], coins_y0[4];
  double tmp;
  int upside_down;
  int i;
  int student, page, question, answer;
  point box[4];
  linear_transform transfo, transfo_back;
  double mse;

  cv::Mat src;
  cv::Mat dst;
  cv::Mat illustr;
  cv::Mat src_calage;

  int illustr_mode = ILLUSTR_BOX;

  char *scan_file = NULL;
  char *out_image_file = NULL;
  char *zooms_dir = NULL;
  int view = 0;
  int post_process_image = 0;
  int ignore_red = 0;

#if OPENCV_20
  vector<int> save_options;
  save_options.push_back(cv::IMWRITE_JPEG_QUALITY);
  save_options.push_back(75);
#endif

  // Options
  // -x tx : gives the width of the original subject
  // -y ty : gives the height of the opriginal subject
  // -d d  : gives the diameter of the corner marks on the original subject
  // -p dp : gives the tolerance above mark diameter (fraction of the diameter)
  // -m dm : gives the tolerance below mark diameter
  // -c n  : gives the minimum requested number of corner marks
  // -t th : gives the threshold to convert to black&white
  // -o file : gives output file name for detected layout report image
  // -v / -P : asks for marks detection debugging image report

  char c;
  while ((c = getopt(argc, argv, "x:y:d:i:p:m:t:c:o:vPrk")) != -1) {
    switch (c) {
    case 'x': taille_orig_x = atof(optarg); break;
    case 'y': taille_orig_y = atof(optarg); break;
    case 'd': dia_orig = atof(optarg); break;
    case 'p': tol_plus = atof(optarg); break;
    case 'm': tol_moins = atof(optarg); break;
    case 't': threshold = atof(optarg); break;
    case 'c': n_min_cc = atoi(optarg); break;
    case 'o': out_image_file = strdup(optarg); break;
    case 'v': view = 1; break;
    case 'r': ignore_red = 1; break;
    case 'P': post_process_image = 1; view = 2; break;
    case 'k': illustr_mode=ILLUSTR_PIXELS; break;
    }
  }

  printf("TX=%.2f TY=%.2f DIAM=%.2f\n", taille_orig_x, taille_orig_y, dia_orig);

  size_t commande_t;
  char* commande = NULL;
  char* endline;
  char text[128];
  char shape_name[32];
  int shape_id;

  cv::Point textpos;
  double fh;

  while(getline(&commande, &commande_t, stdin) >= 6) {
    //printf("LC_NUMERIC: %s\n",setlocale(LC_NUMERIC,NULL));

    if((endline=strchr(commande, '\r')))
        *endline='\0';
    if((endline=strchr(commande, '\n')))
        *endline='\0';

    if(processing_error == 0) {

      if(strncmp(commande, "output ", 7) == 0) {
        free(out_image_file);
        out_image_file = strdup(commande + 7);
      } else if(strncmp(commande,"zooms ", 6)==0) {
        free(zooms_dir);
        zooms_dir = strdup(commande + 6);
      } else if(strncmp(commande,"load ", 5)==0) {
        free(scan_file);
        scan_file = strdup(commande + 5);

        if(out_image_file != NULL
           && !post_process_image) {
	  try {
	    illustr = cv::imread(scan_file, cv::IMREAD_COLOR);
	  } catch (const cv::Exception& ex) {
            printf("! LOAD : Error loading scan file in COLOR [%s]\n", scan_file);
	    printf("! OpenCV error: %s\n", ex.what());
            processing_error = 4;
	  }
	  printf(": Image background loaded\n");
        }

        load_image(src,scan_file, ignore_red, threshold, view);
        printf(": Image loaded\n");

        if(processing_error == 0) {
          src_calage = src.clone();
          if(src_calage.data == NULL) {
            printf("! LOAD : Error cloning image\n");
            processing_error = 5;
          }
        }
        if(processing_error == 0) {
          calage(src_calage,
                 illustr,
                 taille_orig_x,
                 taille_orig_y,
                 dia_orig,
                 tol_plus,
                 tol_moins,
                 n_min_cc,
                 coins_x,
                 coins_y,
                 dst,
                 view);

          upside_down = 0;
        }

        if(out_image_file != NULL && illustr.data == NULL) {
          printf(": Storing layout image\n");
          illustr = dst;
          dst = cv::Mat();
        }

        src_calage.release();

      } else if((sscanf(commande,"optim3 %lf,%lf %lf,%lf %lf,%lf %lf,%lf",
                        &coins_x0[0], &coins_y0[0],
                        &coins_x0[1], &coins_y0[1],
                        &coins_x0[2], &coins_y0[2],
                        &coins_x0[3], &coins_y0[3]) == 8)
                || (strncmp(commande,"reoptim3",8) == 0) ) {
        /* TRYING TO OMIT EACH CORNER IN TURN */
        /* "optim3" and 8 arguments: 4 marks positions (x y,
           order: UL UR BR BL)
           return: optimal linear transform and MSE */
        /* "reoptim3": optim with the same arguments as for last "optim" call */
        mse = omit_optim(coins_x0, coins_y0, coins_x, coins_y, 4, &transfo);
        printf("Transfo:\na=%f\nb=%f\nc=%f\nd=%f\ne=%f\nf=%f\n",
               transfo.a, transfo.b,
               transfo.c, transfo.d,
               transfo.e, transfo.f);
        printf("MSE=0.0\n");
        printf("QUALITY=%f\n", mse);

        revert_transform(&transfo, &transfo_back);

      } else if((sscanf(commande,"optim %lf,%lf %lf,%lf %lf,%lf %lf,%lf",
                        &coins_x0[0], &coins_y0[0],
                        &coins_x0[1], &coins_y0[1],
                        &coins_x0[2], &coins_y0[2],
                        &coins_x0[3], &coins_y0[3]) == 8)
                || (strncmp(commande,"reoptim",7) == 0) ) {
        /* "optim" and 8 arguments: 4 marks positions (x y,
           order: UL UR BR BL)
           return: optimal linear transform and MSE */
        /* "reoptim": optim with the same arguments as for last "optim" call */
        mse = optim(coins_x0,coins_y0,coins_x,coins_y,4,&transfo);
        printf("Transfo:\na=%f\nb=%f\nc=%f\nd=%f\ne=%f\nf=%f\n",
               transfo.a, transfo.b,
               transfo.c, transfo.d,
               transfo.e, transfo.f);
        printf("MSE=%f\n",mse);

        revert_transform(&transfo, &transfo_back);

      } else if(strncmp(commande,"rotateOK",8) == 0) {
        /* validates upside down rotation */
        if(upside_down) {
          transfo.a = - transfo.a;
          transfo.b = - transfo.b;
          transfo.c = - transfo.c;
          transfo.d = - transfo.d;
          transfo.e = (src.cols - 1) - transfo.e;
          transfo.f = (src.rows - 1) - transfo.f;

          if(src.data != NULL)
              cv::flip(src, src, -1);
          if(illustr.data != NULL)
              cv::flip(illustr, illustr, -1);
          if(dst.data != NULL)
              cv::flip(dst, dst, -1);

          for(i = 0; i < 4; i++) {
            coins_x[i] = (src.cols - 1) - coins_x[i];
            coins_y[i] = (src.rows - 1) - coins_y[i];
          }

          upside_down = 0;

          printf("Transfo:\na=%f\nb=%f\nc=%f\nd=%f\ne=%f\nf=%f\n",
                 transfo.a, transfo.b,
                 transfo.c, transfo.d,
                 transfo.e, transfo.f);

          revert_transform(&transfo, &transfo_back);
        }
      } else if(strncmp(commande,"rotate180", 9) == 0) {
        for(i = 0; i < 2; i++) {
          SWAP(coins_x[i], coins_x[i+2], tmp);
          SWAP(coins_y[i], coins_y[i+2], tmp);
        }
        upside_down = 1 - upside_down;
        printf("UpsideDown=%d\n", upside_down);
      } else if(sscanf(commande,"id %d %d %d %d",
                       &student, &page, &question, &answer) == 4) {
        /* box id */
      } else if(sscanf(commande, "mesure0 %lf %s %lf %lf %lf %lf",
                       &prop, shape_name,
                       &xmin, &xmax, &ymin, &ymax) == 6) {
        /* "mesure0" and 6 arguments: proportion, shape, xmin, xmax, ymin, ymax
           return: number of black pixels and total number of pixels */
        transforme(&transfo, xmin, ymin, &box[0].x, &box[0].y);
        transforme(&transfo, xmax, ymin, &box[1].x, &box[1].y);
        transforme(&transfo, xmax, ymax, &box[2].x, &box[2].y);
        transforme(&transfo, xmin, ymax, &box[3].x, &box[3].y);

        if(strcmp(shape_name,"oval") == 0) {
          shape_id = SHAPE_OVAL;
        } else {
          shape_id = SHAPE_SQUARE;
        }

        /* output transformed points */
        for(i = 0; i < 4; i++) {
          printf("TCORNER %.3f,%.3f\n", box[i].x, box[i].y);
        }

        mesure_case(src, illustr, illustr_mode,
                    student, page, question, answer,
                    prop, shape_id,
                    xmin, xmax, ymin, ymax, &transfo_back,
                    box, dst, zooms_dir, view);
        student = -1;
      } else if(sscanf(commande,"mesure %lf %lf %lf %lf %lf %lf %lf %lf %lf",
                       &prop,
                       &box[0].x, &box[0].y,
                       &box[1].x, &box[1].y,
                       &box[2].x, &box[2].y,
                       &box[3].x, &box[3].y) == 9) {
        /* "mesure" and 9 arguments: proportion, and 4 vertices
           (x y, order: UL UR BR BL)
           returns: number of black pixels and total number of pixels */
        mesure_case(src, illustr, illustr_mode,
                    student, page, question, answer,
                    prop, SHAPE_SQUARE,
                    -1, -1, -1, -1, NULL,
                    box, dst, zooms_dir, view);
        student = -1;
      } else if(strlen(commande) < 100 &&
                sscanf(commande, "annote %s", text) == 1) {
        fh = src.rows / 50.0;
        textpos.x = 10;
        textpos.y = (int)(1.6 * fh);
        cv::putText(illustr, text, textpos, cv::FONT_HERSHEY_PLAIN, fh/14, BLEU, 1+(int)(fh/20), cv::LINE_AA);
      } else {
        printf(": %s\n", commande);
        printf("! SYNERR : Syntax error\n");
      }

    } else {
      printf("! ERROR : not responding due to previous error.\n");
    }

    printf("__END__\n");
    fflush(stdout);
  }

#ifdef OPENCV_21
#ifdef AMC_DETECT_HIGHGUI
  if(view == 1) {
    cv::namedWindow("Source", cv::WINDOW_NORMAL);
    cv::imshow("Source", src);
    cv::namedWindow("Components", cv::WINDOW_NORMAL);
    cv::imshow("Components", dst);
    cv::waitKey(0);

    dst.release();
  }
#endif
#endif

  if(illustr.data && strlen(out_image_file) > 1) {
    printf(": Saving layout image to %s\n", out_image_file);
    try {
      cv::imwrite(out_image_file, illustr
#if OPENCV_20
		  , save_options
#endif
		  );
    } catch (const cv::Exception& ex) {
      printf("! LAYS : Layout image save error: %s\n", ex.what());
    }
  }

  illustr.release();
  src.release();

  free(commande);
  free(scan_file);

  return(0);
}

